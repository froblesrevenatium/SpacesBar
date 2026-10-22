# SpacesBar

Indicador para la barra de menús de macOS, al estilo del módulo de workspaces de Waybar: muestra cada escritorio (Space) con su número y los íconos de las apps que tienen ventanas en él. El escritorio activo aparece en una cápsula con el color de énfasis del sistema (el número cambia a oscuro o claro según el contraste); los demás, sin fondo ni borde. Un clic cambia de escritorio.

```
[1 ▣ ▣ ▣] (2 ▣) (3 ▣) (4)
```

Junto con **Amethyst** en layout de columnas, forma un entorno parecido a Hyprland + Waybar: ventanas en mosaico automático, escritorios numerados visibles y cambio rápido entre ellos.

## Dependencias

| Dependencia | Para qué | Estado / cómo obtenerla |
|---|---|---|
| macOS 13 o superior | `SMAppService`, APIs de Spaces | Probado en macOS 26.6.2 |
| Xcode Command Line Tools (`swiftc`, `make`, `codesign`) | Compilar e instalar | `xcode-select --install` (probado con Swift 6.3.3) |
| Atajos de Mission Control "Cambiar al escritorio N" | Cambiar de escritorio con clic (SpacesBar) y mover ventanas entre escritorios (Amethyst) | Ver [Configuración de macOS](#configuración-de-macos) |
| "Reorganizar automáticamente los Spaces" **desactivado** | Que los números de escritorio no cambien solos | Ver [Configuración de macOS](#configuración-de-macos) |
| Barra de menús **siempre visible** | Que las ventanas no queden debajo de la barra | Ver [Configuración de macOS](#configuración-de-macos) |
| Permiso de Accesibilidad | SpacesBar: enviar el atajo de cambio de escritorio. Amethyst: mover y redimensionar ventanas | Ver [Permisos](#permisos) |
| [Amethyst](https://ianyh.com/amethyst/) con layout `column` | Mosaico automático de ventanas al estilo Hyprland | `brew install --cask amethyst` — ver [Amethyst](#amethyst-mosaico-al-estilo-hyprland) |

SpacesBar no tiene dependencias de terceros: un solo `main.swift` con AppKit, ApplicationServices y ServiceManagement.

## Instalación

```sh
make install
```

Compila `SpacesBar.app`, la copia a `/Applications` y la abre. Para que arranque con el Mac: clic derecho en el indicador → **Abrir al iniciar sesión**.

| Comando          | Qué hace                                    |
|------------------|---------------------------------------------|
| `make build`     | Compila `SpacesBar.app` en este directorio  |
| `make install`   | Compila, instala en `/Applications` y abre  |
| `make uninstall` | Cierra la app y la borra de `/Applications` |

## Configuración de macOS

1. **Atajos de escritorio**: Configuración del Sistema → Teclado → Funciones rápidas de teclado → Mission Control → activar "Cambiar al escritorio 1…N". Solo aparecen los escritorios que ya existen: créalos primero desde Mission Control. Hoy están activos `⌃1`–`⌃3`; falta activar el 4.
2. **No reorganizar escritorios**: Configuración del Sistema → Escritorio y Dock → Mission Control → desactivar "Reorganizar automáticamente los Spaces según el uso más reciente" (actualmente desactivado: `defaults read com.apple.dock mru-spaces` = `0`).
3. **Barra de menús fija**: Configuración del Sistema → Centro de control → "Ocultar y mostrar automáticamente la barra de menús" → **Nunca**. macOS no permite que una app reserve espacio en pantalla; con la barra visible el sistema lo reserva y SpacesBar queda dentro de ella.

## Amethyst: mosaico al estilo Hyprland

[Amethyst](https://ianyh.com/amethyst/) (instalado, versión 0.24.3) acomoda las ventanas automáticamente. El layout **column** las reparte en columnas de igual ancho, lado a lado, lo más parecido al mosaico de Hyprland.

### Instalación

```sh
brew install --cask amethyst
```

Al abrirlo pide permiso de Accesibilidad. Para que arranque con el Mac, agrégalo en Configuración del Sistema → General → Ítems de inicio.

### Layout de columnas

Configuración actual de layouts: `tall, wide, fullscreen, column` (`column` es el cuarto). Para usarlo:

- En el escritorio actual: `⌥⇧F` (seleccionar layout column).
- Como layout por defecto en todos los escritorios, ponerlo primero en la lista y relanzar Amethyst:

  ```sh
  defaults write com.amethyst.Amethyst layouts -array column tall wide fullscreen
  ```

  Luego `⌃⌥⇧Z` (relaunch Amethyst) o ciérralo y ábrelo. También se puede ordenar desde Preferencias → Layouts.

### Atajos configurados

`mod1` = `⌥⇧` · `mod2` = `⌃⌥⇧`

| Atajo | Acción | Equivalente Hyprland |
|---|---|---|
| `⌥⇧J` / `⌥⇧K` | Enfocar ventana anterior / siguiente | `movefocus` |
| `⌃⌥⇧J` / `⌃⌥⇧K` | Intercambiar con la anterior / siguiente | `swapwindow` |
| `⌥⇧↩` | Mover ventana a la posición principal | `layoutmsg swapwithmaster` |
| `⌥⇧M` | Enfocar ventana principal | — |
| `⌃⌥⇧1`…`⌃⌥⇧4` | Enviar ventana al escritorio N (y seguirla) | `movetoworkspace` |
| `⌃1`…`⌃4` | Cambiar al escritorio N (Mission Control) | `workspace N` |
| `⌥⇧F` / `⌥⇧A` / `⌥⇧D` | Layout column / tall / fullscreen | `layoutmsg` |
| `⌥⇧,` | Agregar ventana al área principal | — |
| `⌥⇧Z` | Reacomodar ventanas | — |
| `⌃⌥⇧T` | Activar / desactivar mosaico | `togglefloating` global |

"Enviar ventana al escritorio N" usa por debajo los atajos de Mission Control: el escritorio destino debe tener su atajo activado (paso 1 de [Configuración de macOS](#configuración-de-macos)).

### Convivencia con SpacesBar

- Son independientes: Amethyst acomoda ventanas dentro de cada escritorio; SpacesBar muestra los escritorios y cambia entre ellos.
- Ambos usan los mismos atajos de Mission Control y requieren Accesibilidad.
- Con la barra de menús siempre visible, Amethyst deja libre la franja superior (`ignore-menu-bar` = `0`), así que el mosaico no tapa SpacesBar.

## Uso de SpacesBar

### Qué muestra

- Los escritorios se numeran igual que en Mission Control (1, 2, 3…). Los espacios de pantalla completa no llevan número, solo el ícono de la app.
- Con varios monitores, cada pantalla se separa con una línea vertical y la numeración continúa.
- Hasta 6 íconos por escritorio, del frente hacia atrás; el resto aparece como `+n`.
- Solo cuenta apps normales (con ícono en el Dock) y ventanas mayores a 50×50 px. Las ventanas minimizadas y las apps ocultas (`⌘H`) no aparecen.
- Se actualiza al cambiar de escritorio, abrir, cerrar, activar u ocultar apps, y cada 1.5 s para detectar ventanas movidas entre escritorios.

### Posición: derecha o centro

Clic derecho → **Mostrar en el centro** (se recuerda entre reinicios).

- **Derecha** (por defecto): ícono normal de la barra de menús (`NSStatusItem`). macOS no permite colocar estos íconos en otra posición.
- **Centro**: ventana flotante sin bordes ni fondo, a nivel de la barra de menús y centrada en cada pantalla. Ocupa la altura de la barra menos 2 px arriba y abajo (26 px en una barra de 30 px), con íconos de 22 px.
  - En pantallas con notch se coloca a la derecha del notch.
  - No aparece en apps a pantalla completa.
  - Si el menú de la app activa es muy largo, puede quedar debajo del indicador.

### Cambiar de escritorio con clic

- **Clic izquierdo** en un escritorio: cambia a él.
- **Clic derecho** (o `⌃`+clic): abre el menú.

Cómo cambia, en orden:

1. Si el escritorio tiene activado su atajo de Mission Control, SpacesBar envía ese atajo, sea cual sea la combinación configurada (lee `com.apple.symbolichotkeys`).
2. Si no tiene atajo pero tiene apps (incluye pantalla completa), activa la primera app y macOS cambia a ese escritorio. Si esa app tiene ventanas en varios escritorios, macOS puede elegir otro.
3. Si no tiene atajo ni apps, muestra un aviso con el atajo que hay que activar.

## Permisos

- **Accesibilidad** (SpacesBar): solo para cambiar de escritorio con clic. El primer clic abre el aviso de macOS; actívalo en Configuración del Sistema → Privacidad y seguridad → Accesibilidad → SpacesBar.
  - La app está firmada ad-hoc: cada `make install` cambia la firma y macOS invalida el permiso. Tras reinstalar, quita SpacesBar de la lista con **−** y vuelve a agregarla.
- **Accesibilidad** (Amethyst): necesaria para que acomode ventanas.
- Mostrar escritorios y apps no requiere permisos: solo se usa la app dueña de cada ventana, no su título (que pediría Grabación de pantalla).

## Historial de lo realizado

| Paso | Resultado |
|---|---|
| Instalar **Spaceman** (`brew install --cask spaceman`) | Mostraba solo los escritorios, sin apps. Reemplazado por SpacesBar; se puede quitar con `brew uninstall --cask spaceman` |
| Crear **SpacesBar** | Escritorios numerados con íconos de sus apps, escritorio activo resaltado, modo claro/oscuro |
| Opción **Mostrar en el centro** | Ventana flotante centrada, porque `NSStatusItem` solo vive a la derecha |
| **Clic para cambiar de escritorio** | Envía el atajo de Mission Control; respaldo activando una app del escritorio |
| **Reloj** en el indicador | Agregado y luego **eliminado**: se mantiene el reloj de macOS |
| **Reservar espacio** moviendo ventanas con Accesibilidad | Agregado y luego **eliminado**: el ajuste posterior al maximizar causaba un parpadeo notable. Se optó por la barra de menús siempre visible |
| **Amethyst** con layout `column` | Mosaico automático al estilo Hyprland (documentado como dependencia) |

## Notas técnicas

- Usa APIs privadas de SkyLight (`CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows`), las mismas que usan Spaceman, yabai y AeroSpace. Una actualización de macOS podría cambiarlas.
- Preferencias en `com.fernandorobles.spacesbar` (`showInCenter`).
- Inicio de sesión con `SMAppService.mainApp` (aparece en Configuración del Sistema → General → Ítems de inicio).
