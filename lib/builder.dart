import 'package:bloc_error_control/src/generator/error_mapper_generator.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

Builder errorMapperBuilder(BuilderOptions options) =>
    PartBuilder([ErrorMapperGenerator()], '.error.g.dart');
