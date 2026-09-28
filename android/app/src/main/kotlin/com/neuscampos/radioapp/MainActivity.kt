package com.neuscampos.radioapp

// audio_service requiere que la Activity herede de AudioServiceActivity (no del
// FlutterActivity por defecto); si no, AudioService.init lanza
// "The Activity class declared in your AndroidManifest.xml is wrong".
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
