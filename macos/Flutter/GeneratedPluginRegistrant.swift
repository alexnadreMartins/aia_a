//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import desktop_drop
import face_detection_tflite
import path_provider_foundation
import screen_retriever
import window_manager

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  DesktopDropPlugin.register(with: registry.registrar(forPlugin: "DesktopDropPlugin"))
  FaceDetectionTflitePlugin.register(with: registry.registrar(forPlugin: "FaceDetectionTflitePlugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
  ScreenRetrieverPlugin.register(with: registry.registrar(forPlugin: "ScreenRetrieverPlugin"))
  WindowManagerPlugin.register(with: registry.registrar(forPlugin: "WindowManagerPlugin"))
}
