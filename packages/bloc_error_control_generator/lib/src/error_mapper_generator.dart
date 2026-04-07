// ignore_for_file: depend_on_referenced_packages, implementation_imports, deprecated_member_use
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:bloc_error_control/src/annotations/annotations.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Code generator for `@BlocErrorControl` annotation.
///
/// This generator reads the `bloc_error_control_mixin.dart` template file,
/// extracts all `@ErrorStateFor` annotated methods from the annotated class,
/// and generates an extension that wires up the error mappers.
///
/// The generated code includes:
/// - A `getErrorMapperForEvent` method that routes errors to the appropriate mapper
/// - Proper type casting between event types
/// - Seamless integration with the `BlocErrorControlMixin`
class ErrorMapperGenerator extends GeneratorForAnnotation<BlocErrorControl> {
  String? _templateCache;

  @override
  Future<String?> generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) async {
    // Ensure annotation is on a class
    if (element is! ClassElement) {
      return null;
    }

    final classElement = element;

    // Read the mixin template file
    final assetId = AssetId('bloc_error_control', 'lib/src/mixins/bloc_error_control_mixin.dart');

    String templateFull;
    try {
      _templateCache ??= await buildStep.readAsString(assetId);
      templateFull = _templateCache ?? '';
    } on Object catch (e) {
      throw InvalidGenerationSourceError(
        'Failed to locate template file at: ${assetId.path}'
        '\nError: $e',
      );
    }
    if (templateFull.isEmpty) {
      throw InvalidGenerationSourceError('Failed to read template file at: ${assetId.path}!');
    }

    // Extract the template body between markers
    final regExpBlock = RegExp(r'// {{REG_BEGIN}}([\s\S]*?)// {{REG_END}}');
    final matchBlock = regExpBlock.firstMatch(templateFull);
    if (matchBlock == null) {
      return null;
    }
    final templateBody = matchBlock.group(1)!;

    // Collect mappers for this specific class
    final mappers = <_MapperModel>[];

    for (final method in classElement.methods) {
      final eventTypes = <DartType>[];
      final dynamic rawMetadata = method.metadata;
      List<ElementAnnotation> annotations;

      try {
        annotations = (rawMetadata as Iterable).cast<ElementAnnotation>().toList();
      } on Object catch (_) {
        try {
          annotations = (rawMetadata.annotations as Iterable).cast<ElementAnnotation>().toList();
        } on Object catch (_) {
          annotations = <ElementAnnotation>[];
          for (var i = 0; i < (rawMetadata.length as int); i++) {
            annotations.add(rawMetadata[i] as ElementAnnotation);
          }
        }
      }

      for (final meta in annotations) {
        final value = meta.computeConstantValue();
        final type = value?.type;
        if (type == null) {
          continue;
        }
        final annotationName = meta.element?.displayName ?? '';
        if (annotationName.contains('ErrorStateFor')) {
          if (type is InterfaceType && type.typeArguments.isNotEmpty) {
            final typeArg = type.typeArguments.first;
            eventTypes.add(typeArg);
          } else {
            try {
              final dynamic metaDynamic = meta;
              final DartType? typeArg = metaDynamic.typeArguments?.first;
              if (typeArg != null) {
                eventTypes.add(typeArg);
              }
            } on Object catch (_) {}
          }
        }
      }

      if (eventTypes.isEmpty) {
        continue;
      }

      _validate(method, eventTypes);

      for (final type in eventTypes) {
        final methodName = method.name ?? '';
        mappers.add(
          _MapperModel(
            eventTypeName: type.getDisplayString(withNullability: false),
            methodName: methodName,
          ),
        );
      }
    }

    // Generate code if mappers were found
    if (mappers.isNotEmpty) {
      final blocType = classElement.allSupertypes.where((t) {
        final name = t.element.name ?? '';
        return name == 'Bloc' || name.contains('Bloc');
      }).firstOrNull;
      if (blocType == null) {
        return null;
      }

      final eType = blocType.typeArguments[0].getDisplayString(withNullability: false);
      final sType = blocType.typeArguments[1].getDisplayString(withNullability: false);

      final mapperCode = '''
  @protected
  String get tag => runtimeType.toString();
  
  @protected
  S? getErrorMapperForEvent(Object error, StackTrace stackTrace, E event) {
    return switch (event) {
      ${mappers.map((m) => '${m.eventTypeName} e => (this as dynamic).${m.methodName}(error, stackTrace, e),').join('\n      ')}
      _ => null,
    };
  }''';

      final generatedContent = templateBody
          .replaceFirst(
            RegExp(r'mixin\s+BlocErrorControlMixin<E\s+extends\s+Object,\s+S>'),
            'mixin _\$${classElement.name}ErrorMapper<E extends $eType, S extends $sType>',
          )
          .replaceFirst(RegExp(r'// {{MAPPER_REPLACE}}[\s\S]*?// {{MAPPER_REPLACE}}'), mapperCode);
      return '''
            // coverage:ignore-file
            // ignore_for_file: type=lint
            // ignore_for_file: avoid_dynamic_calls, argument_type_not_assignable, implementation_imports
            
            $generatedContent''';
    }

    return null;
  }

  /// Validates that a mapper method has the correct signature.
  ///
  /// Expected signature: (Object error, StackTrace stack, EventType event)
  void _validate(MethodElement method, List<DartType> eventTypes) {
    final dynamic methodElement = method;
    final dynamic rawParams = _getFormalParameters(methodElement) ?? _getParameters(methodElement);

    if (rawParams == null) {
      throw InvalidGenerationSourceError(
        'Failed to retrieve parameters for method ${method.name}. '
        'Check the version of the analyzer package.',
        element: method,
      );
    }
    final parameters = (rawParams as Iterable).toList();

    if (parameters.length != 3) {
      throw InvalidGenerationSourceError(
        'Method ${method.name} must accept exactly 3 arguments: (Object error, StackTrace stack, T event)',
        element: method,
      );
    }

    final param3 = parameters[2];
    final param3Type = param3.type;

    for (final type in eventTypes) {
      // Check type compatibility through the library's type system
      final isAssignable = method.library.typeSystem.isAssignableTo(type, param3Type);

      if (!isAssignable) {
        final expectedName = type.getDisplayString(withNullability: false);
        final actualName = param3Type.getDisplayString(withNullability: false);

        throw InvalidGenerationSourceError(
          'Error in method ${method.name}:\n'
          'The annotation expects an event of type [$expectedName],\n'
          'but the method argument has type [$actualName].\n'
          'They must be compatible.',
          element: param3,
        );
      }
    }
  }

  dynamic _getFormalParameters(dynamic element) {
    try {
      return element.formalParameters;
    } on Object catch (_) {
      return null;
    }
  }

  dynamic _getParameters(dynamic element) {
    try {
      return element.parameters;
    } on Object catch (_) {
      return null;
    }
  }
}

/// Internal model for storing mapper information.
class _MapperModel {
  /// The fully qualified name of the event type (e.g., 'LoadUserEvent').
  final String eventTypeName;

  /// The name of the mapper method.
  final String methodName;

  _MapperModel({required this.eventTypeName, required this.methodName});
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
