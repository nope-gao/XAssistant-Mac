# XAssistant Mac

[简体中文](README.md) | [繁體中文](README.zh-Hant.md) | [English](README.en.md) | [日本語](README.ja.md) | **Español** | [Français](README.fr.md) | [Deutsch](README.de.md)

Herramienta local para macOS que registra la actividad del teclado y el ratón y exporta vídeos animados con mapas de calor 3D.

Adaptada de las funciones e ideas de [xuhk/XAssistant](https://github.com/xuhk/XAssistant), reimplementada de forma nativa en Swift. Es una versión no oficial para macOS, sin afiliación con el autor original. No se copió código ni material del proyecto de Windows. Disponible bajo la [licencia MIT](LICENSE).

## Funciones

- Registro en segundo plano desde la barra de menús, con estadísticas diarias y mapas de calor del teclado.
- Detección de teclados integrados y externos, con distribuciones MacBook y Mac de tamaño completo y selección manual.
- Selección de inicio y fin, con accesos a la primera grabación y a la hora actual.
- Exportación de pulsaciones animadas y mapas acumulativos como MP4 de 1080p a 30 fps en Descargas, comprimiendo automáticamente los intervalos inactivos.
- Inclusión o exclusión del ratón; velocidades de 0.5× a 256×, incluida 128×.
- Escala de color dinámica según el mayor recuento acumulado actual, o fija según el mayor total final del intervalo seleccionado.
- La imagen final permanece cinco segundos mientras la cámara gira lentamente.
- Sonido sincronizado en cada pulsación, distinto para cada tecla física, con perfiles de teclado, mecánico, suave o silencio.

## Instalación

Requiere **Apple Silicon y macOS 13 o posterior**. La aplicación descargada no necesita Xcode.

- **Descarga directa:** abre la [última versión](https://github.com/nope-gao/XAssistant-Mac/releases/latest), descarga `XAssistant-Mac-arm64.zip`, descomprímelo y mueve **XAssistant Mac.app** a `~/Applications`.
- **Instalación o actualización desde Terminal:** cierra primero la aplicación y ejecuta:

```bash
curl -fsSL https://raw.githubusercontent.com/nope-gao/XAssistant-Mac/main/install.sh -o /tmp/xassistant-install.sh && bash /tmp/xassistant-install.sh
```

El instalador descarga la última versión, verifica SHA-256 y comprueba que la nueva firma cumpla los requisitos de la aplicación instalada. Detiene las actualizaciones incompatibles antes de reemplazarla. Instala en `~/Applications` sin sudo y conserva las grabaciones. Debe existir una versión con el ZIP de la aplicación adjunto; el ZIP Source code que genera GitHub contiene código, no la aplicación.

La descarga existente de v0.4.0 tiene firma ad-hoc y no está notarizada por Apple. Si macOS la bloquea, comprueba su procedencia y utiliza **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente**. Después, concede la monitorización de entrada.

## Idioma

El ajuste inicial es **Seguir el sistema**. La aplicación recorre la lista de idiomas preferidos de macOS y elige uno compatible: **简体中文, 繁體中文, English, 日本語, Español, Français, Deutsch**. Si no hay coincidencias, utiliza inglés. Puedes elegir otro idioma o volver al sistema en la parte inferior de la ventana; la preferencia se guarda.

El idioma se aplica a la interfaz, menús, mensajes existentes, fechas y números, etiquetas del ratón, nombres de teclas de función y subtítulos del vídeo. Las letras conservan la distribución física ANSI. El vídeo mantiene el idioma seleccionado al iniciar la exportación; durante ella no se permite cambiarlo manualmente. macOS controla el idioma de sus propios diálogos de permisos y de los detalles de errores del sistema.

## Sonido del vídeo

Elige **Teclado** (predeterminado), **Mecánico**, **Suave** o **Silencio**. Cada tecla física tiene un timbre corto y distinto, que se activa solo al pulsarla y coincide con el primer fotograma que muestra la pulsación. Las pulsaciones densas se mezclan a velocidades altas. Excluir el ratón también excluye sus clics. Los cinco segundos finales permanecen en silencio.

El audio se sintetiza localmente: no utiliza el micrófono, no graba tu teclado real ni requiere archivos de sonido externos. Los vídeos con sonido incluyen una pista AAC de 48 kHz; el modo Silencio no genera pista de audio.

## Compilar desde el código

Se necesitan Xcode Command Line Tools. El script solo genera aplicaciones ARM64; no se ha verificado la compatibilidad con todas las versiones de macOS admitidas.

Ejecuta el primer comando solo si faltan las herramientas de desarrollo. Compila desde la carpeta del proyecto; se incluyen comprobaciones de firma y pruebas internas. Cierra cualquier copia en ejecución antes de instalar.

```bash
xcode-select --install
bash build.sh
mkdir -p "$HOME/Applications"
ditto "dist/XAssistant Mac.app" "$HOME/Applications/XAssistant Mac.app"
open "$HOME/Applications/XAssistant Mac.app"
```

La compilación local usa firma ad-hoc por defecto, sin Developer ID ni notarización. Reemplazar una instalación puede invalidar sus permisos.

## Uso y permisos

Después del primer inicio, abre **Ajustes del Sistema → Privacidad y seguridad → Monitorización de entrada**, permite **XAssistant Mac** desde su ubicación instalada y cierra y vuelve a abrir la aplicación. Usa el teclado y el ratón y comprueba que la fecha del último registro y los recuentos cambian realmente antes de exportar.

Compilar o reemplazar la aplicación puede invalidar la autorización. Si el permiso está activado pero no hay registros, cierra la aplicación y ejecuta:

```bash
tccutil reset ListenEvent local.jasongao.xassistantmac
```

Añade de nuevo la aplicación instalada a Monitorización de entrada, activa el permiso y reiníciala. El comando solo restablece este permiso para esta aplicación.

Selecciona el intervalo, velocidad, ratón, escala de calor y sonido, y pulsa **Exportar a Descargas**. No se puede recuperar actividad de periodos sin grabación.

## Datos locales y privacidad

Los datos se guardan en `~/Library/Application Support/XAssistantMac/`. La aplicación no los sube ni incluye telemetría. El instalador accede a GitHub para descargar versiones.

Para reproducir animaciones se guardan las horas de pulsación y liberación, identificadores de teclas físicas, información del dispositivo y orden de eventos. También se registran nombres de aplicaciones, Bundle ID y tiempo de uso. No se lee el texto final de los métodos de entrada, títulos de ventanas, direcciones web ni coordenadas del ratón. **La secuencia de teclas puede permitir inferir el texto escrito. Las grabaciones son datos sensibles; no publiques la carpeta de datos.**

## Limitaciones conocidas

- Principalmente distribuciones ANSI. ISO/JIS no están totalmente adaptadas y la detección automática puede no reconocer todos los dispositivos de terceros.
- Las teclas Fn, multimedia y la entrada segura pueden no registrarse por completo. Touch ID no se registra como una tecla normal.
- El origen de los eventos puede ser ambiguo al usar varios teclados. La repetición automática al mantener una tecla no se cuenta como pulsaciones independientes.
- Los vídeos se generan directamente con SceneKit, Metal y AVFoundation; no requieren Blender.

## Publicar una actualización (mantenimiento)

La versión v0.4.0 existente usa firma ad-hoc. Alternar el permiso puede conservar el requisito de firma antiguo y dejar el interruptor activado sin registrar. Las futuras versiones **requieren una identidad estable Developer ID Application**; si falta el certificado, se bloquea la publicación.

Configura los secretos de GitHub Actions `SIGNING_CERTIFICATE_BASE64` (P12 en Base64), `SIGNING_CERTIFICATE_PASSWORD` y `SIGNING_IDENTITY`. Nunca subas la clave privada al repositorio. El flujo importa el certificado a un llavero temporal y lo elimina al terminar. Mantén la misma identidad en las actualizaciones. La primera migración desde ad-hoc a Developer ID requiere volver a autorizar una vez.

Actualiza la versión y el número de compilación de `build.sh`, confirma los cambios y envía la etiqueta correspondiente:

```bash
git tag v0.4.1
git push origin main --tags
```

Los envíos a main verifican las traducciones, los tiempos de las pulsaciones y la codificación real de audio y vídeo. Las etiquetas publican una versión con ZIP y checksum cuando las pruebas pasan. Usa un número nuevo en cada actualización. También puedes ejecutar `SIGNING_IDENTITY="Developer ID Application: …" bash package.sh` con el certificado instalado localmente y adjuntar `dist/XAssistant-Mac-arm64.zip` y `dist/SHA256SUMS` a la versión de GitHub.

`ALLOW_ADHOC_PACKAGE=1 bash package.sh` es solo para pruebas locales, no para publicar actualizaciones que conserven permisos. Una ruta y Bundle ID fijos no resuelven los cambios de firma ad-hoc. Consulta la [explicación de Apple sobre firmas y acceso privado](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements).
