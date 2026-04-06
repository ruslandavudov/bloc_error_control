// ignore_for_file: depend_on_referenced_packages
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:bloc_error_control/src/annotations/annotations.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Code generator for `@BlocErrorHandler` annotation.
///
/// This generator reads the `bloc_error_control_mixin.dart` template file,
/// extracts all `@ErrorStateFor` annotated methods from the annotated class,
/// and generates an extension that wires up the error mappers.
///
/// The generated code includes:
/// - A `getErrorMapperForEvent` method that routes errors to the appropriate mapper
/// - Proper type casting between event types
/// - Seamless integration with the `BlocErrorHandlerMixin`
class ErrorMapperGenerator extends GeneratorForAnnotation<BlocErrorHandler> {
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
      final annotations = (rawMetadata is Iterable)
          ? rawMetadata.cast<ElementAnnotation>().toList()
          : <ElementAnnotation>[];

      for (final meta in annotations) {
        final value = meta.computeConstantValue();
        final typeName = value?.type?.getDisplayString(withNullability: false);

        if (typeName == 'ErrorStateFor') {
          final typeValue = value?.getField('eventType')?.toTypeValue();
          if (typeValue != null) {
            eventTypes.add(typeValue);
          }
        }
      }

      if (eventTypes.isEmpty) {
        continue;
      }

      _validate(method, eventTypes);

      for (final type in eventTypes) {
        mappers.add(
          _MapperModel(
            eventTypeName: type.getDisplayString(withNullability: false),
            methodName: method.name,
          ),
        );
      }
    }

    // Generate code if mappers were found
    if (mappers.isNotEmpty) {
      final blocType = classElement.allSupertypes.firstWhere(
        (t) => t.element.name == 'Bloc',
        orElse: () =>
            throw InvalidGenerationSourceError('Class ${classElement.name} must extend Bloc'),
      );

      final eType = blocType.typeArguments[0].getDisplayString(withNullability: true);
      final sType = blocType.typeArguments[1].getDisplayString(withNullability: true);

      final mapperCode =
          '''
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
            'mixin BlocErrorHandlerMixin<E extends Object, S>',
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
    final dynamic parameters =
        (method as dynamic).parameters ?? (method as dynamic).formalParameters;

    if (parameters == null || (parameters.length as int) != 3) {
      throw InvalidGenerationSourceError(
        'Method ${method.name} must accept 3 arguments: (Object, StackTrace, Event)',
        element: method,
      );
    }

    final dynamic param3 = parameters[2];
    final param3Type = param3.type as DartType;

    for (final type in eventTypes) {
      final isAssignable = method.library.typeSystem.isAssignableTo(type, param3Type);

      if (!isAssignable) {
        throw InvalidGenerationSourceError(
          'Event ${type.getDisplayString(withNullability: false)} '
          'cannot be passed to parameter of type '
          '${param3Type.getDisplayString(withNullability: false)}.',
          element: param3 as Element,
        );
      }
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
