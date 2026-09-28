/// Acción que el RadioNotifier debe tomar tras evaluar el estado de reproducción
/// del modo vídeo. Función pura → testeable sin tocar players ni ciclo de vida.
enum PlaybackAction {
  /// No hacer nada (el vídeo suena en primer plano).
  none,

  /// Pausar el vídeo y arrancar el stream de audio de la radio en segundo plano.
  startBackgroundAudio,

  /// Parar el audio de fondo y reanudar el vídeo (volvimos a ser visibles).
  stopBackgroundAudioResumeVideo,

  /// Parar el audio de fondo sin reanudar el vídeo (el usuario ya no lo quiere).
  stopBackgroundAudioOnly,
}

/// Decide qué hacer con la reproducción del modo vídeo.
///
/// - [videoMode]: estamos en el modo vídeo de la radio.
/// - [videoIntendedPlaying]: el usuario quiere el vídeo reproduciéndose.
/// - [foreground]: la app está en primer plano (`AppLifecycleState.resumed`).
/// - [backgroundAudioActive]: ya hemos hecho el cambiazo a audio de fondo.
PlaybackAction decidePlayback({
  required bool videoMode,
  required bool videoIntendedPlaying,
  required bool foreground,
  required bool backgroundAudioActive,
}) {
  // Si no estamos en modo vídeo o el usuario no quiere reproducir: solo limpiar
  // el audio de fondo si estaba activo.
  if (!videoMode || !videoIntendedPlaying) {
    return backgroundAudioActive
        ? PlaybackAction.stopBackgroundAudioOnly
        : PlaybackAction.none;
  }
  // El vídeo puede reproducirse si somos visibles: primer plano.
  if (foreground) {
    return backgroundAudioActive
        ? PlaybackAction.stopBackgroundAudioResumeVideo
        : PlaybackAction.none;
  }
  // No visibles (pantalla apagada / segundo plano): audio de fondo.
  return backgroundAudioActive
      ? PlaybackAction.none
      : PlaybackAction.startBackgroundAudio;
}
