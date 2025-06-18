import 'package:equatable/equatable.dart';

class RetreivingFileInfo extends Equatable {
  final String fileName;
  final String? firebasePath;

  const RetreivingFileInfo({
    required this.fileName,
    required this.firebasePath,
  });

  @override
  List<Object?> get props => [fileName, firebasePath];
}
