# Enchufe

App de barra de menú para macOS que muestra cuánta potencia está entrando al cargar, cuánto falta para llenar la batería y la temperatura de la Mac.

```
⚡ 23W · 4m · 43°
```

## Qué muestra

En la barra de menú:

- **Cargando:** watts que entran, tiempo estimado a lleno y temperatura. Ejemplo: `⚡84W · 1h06 · 52°`
- **Enchufada sin cargar:** `🔌 llena` o `🔌 en pausa`, más la temperatura.
- **A batería:** sólo la temperatura.
- El texto pasa a rojo cuando la Mac está caliente (estado térmico serio o crítico, chip a 85 °C o más, o batería a 40 °C o más).

Al hacer clic se abre el detalle:

- Porcentaje de batería y si está cargando
- Potencia nominal del cargador
- Watts que entran de la pared
- Watts que van a la batería (o que salen, en negativo)
- Velocidad de carga (lenta, normal o rápida) y tiempo a lleno
- Temperatura del chip y de la batería
- Estado térmico del sistema
- Opción **Abrir al iniciar sesión**

Se actualiza cada 3 segundos.

## Instalación

Hace falta macOS 13 o superior y las Command Line Tools de Xcode (`xcode-select --install`).

```sh
git clone https://github.com/alu654/enchufe.git
cd enchufe
./build.sh
cp -R Enchufe.app /Applications/
open /Applications/Enchufe.app
```

`build.sh` compila `main.swift`, arma el bundle `Enchufe.app` y lo firma de forma local (ad hoc). No hay dependencias externas.

Para que arranque sola, activá **Abrir al iniciar sesión** desde el menú. Conviene hacerlo con la app ya copiada en `/Applications`.

## Cómo funciona

- **Batería y carga:** lee `AppleSmartBattery` del registro de IOKit (voltaje, amperaje, `AdapterDetails`, `PowerTelemetryData`, `AvgTimeToFull`). Si el sistema no informa el tiempo a lleno, lo calcula con la capacidad restante y la corriente actual.
- **Temperatura:** usa los sensores de IOHID, sin permisos de administrador. Para el chip toma el máximo de los sensores `tdie`; para la batería promedia los sensores de batería y del gas gauge.
- **Inicio de sesión:** `SMAppService`.

Todo está en un solo archivo, `main.swift`.

## Diagnóstico

Para imprimir las lecturas crudas y salir:

```sh
./Enchufe.app/Contents/MacOS/Enchufe --dump
```

## Limitaciones

- Probada en una MacBook con Apple Silicon (M1 Pro). Los nombres de los sensores de temperatura cambian según el modelo, así que en otras Mac puede no aparecer la temperatura.
- Las funciones de IOHID que se usan para leer la temperatura son privadas de Apple y podrían cambiar en futuras versiones de macOS.
- En Mac de escritorio no hay batería, por lo que sólo tendría sentido la parte de temperatura.

## Licencia

[MIT](LICENSE)
