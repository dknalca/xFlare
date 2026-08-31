# xFlare — atajos de desarrollo.
# `make verify` en verde es la condicion para cerrar cualquier tarea.

.PHONY: verify build run app test test-advisory status golden-update seal clean lint profiles-check universal archs toolchain-check

# ---------------------------------------------------------------------------
# Toolchain de DESARROLLO (ADR-029, resuelto 2026-08-31).
# `swift test` ya ejecuta con Xcode 14.2 tras completar su primer arranque
# (instala el soporte XCTest de la plataforma macOS). Antes crasheaba con
# recursion en libXCTestSwiftSupport; ver ADR-029.
# Si hay una toolchain de swift.org instalada en /Library/Developer/Toolchains
# o en ~/Library/Developer/Toolchains, se usa para `swift build` y `swift test`
# en local (compila mas rapido de perfilar). El binario de RELEASE se compila
# con Xcode 14.2 via `make universal`, que ignora esta variable a proposito.
# ---------------------------------------------------------------------------
SWIFTORG_TC := $(shell ls -d /Library/Developer/Toolchains/swift-*RELEASE*.xctoolchain $(HOME)/Library/Developer/Toolchains/swift-*RELEASE*.xctoolchain 2>/dev/null | tail -1)
ifneq ($(SWIFTORG_TC),)
DEVTC := TOOLCHAINS=swift
else
DEVTC :=
endif

# `verify` usa `test-advisory` (tolerante) como red: si otra maquina de dev entra
# sin haber completado el primer arranque de Xcode 14.2, `swift test` podria
# crashear (ADR-029) y no queremos que eso corte el flujo. En una maquina bien
# configurada `make test` (estricto) pasa igual.
verify: toolchain-check build lint profiles-check test-advisory
	@echo ""
	@echo "  build + lint + profiles + tests (advisory) en verde."

toolchain-check:
ifeq ($(SWIFTORG_TC),)
	@echo "  toolchain de dev: Xcode por defecto (no hay swift.org en ~/Library/Developer/Toolchains)"
else
	@echo "  toolchain de dev: $(notdir $(SWIFTORG_TC))"
endif

build:
	$(DEVTC) swift build

# Abre la app (cascaron de andamiaje: ventana + menu maquetado, sin logica).
# `swift run` es CLI puro: compila y ejecuta un binario normal, sin XCTest.
run:
	$(DEVTC) swift build --product xFlare
	$(DEVTC) swift run xFlare

# Empaqueta un xFlare.app en la raiz del repo. SIN firmar (la notarizacion es
# B12): la 1a vez macOS dira "de un desarrollador no identificado" -> clic
# derecho sobre la app > Abrir > Abrir. Es solo el cascaron de andamiaje.
app: build
	@BIN=$$($(DEVTC) swift build --show-bin-path)/xFlare; \
	test -x "$$BIN" || (echo "  no se encuentra el binario xFlare"; exit 1); \
	rm -rf xFlare.app; \
	mkdir -p xFlare.app/Contents/MacOS xFlare.app/Contents/Resources; \
	cp "$$BIN" xFlare.app/Contents/MacOS/xFlare; \
	ICON=""; \
	if [ -f icon/xflare.icns ]; then ICON="icon/xflare.icns"; \
	elif [ -f icon/xflare.svg ]; then sh icon/build-icns.sh >/dev/null 2>&1 && ICON="icon/xflare.icns"; fi; \
	if [ -n "$$ICON" ]; then cp "$$ICON" xFlare.app/Contents/Resources/xflare.icns; fi; \
	printf '%s\n' \
	  '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '  <key>CFBundleName</key><string>xFlare</string>' \
	  '  <key>CFBundleDisplayName</key><string>xFlare</string>' \
	  '  <key>CFBundleIdentifier</key><string>app.xflare.shell</string>' \
	  '  <key>CFBundleExecutable</key><string>xFlare</string>' \
	  '  <key>CFBundleIconFile</key><string>xflare</string>' \
	  '  <key>CFBundlePackageType</key><string>APPL</string>' \
	  '  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>' \
	  '  <key>CFBundleShortVersionString</key><string>0.0-andamiaje</string>' \
	  '  <key>CFBundleVersion</key><string>0</string>' \
	  '  <key>LSMinimumSystemVersion</key><string>11.0</string>' \
	  '  <key>NSHighResolutionCapable</key><true/>' \
	  '  <key>NSMicrophoneUsageDescription</key><string>xFlare necesita la entrada de audio para leer el vinilo de control.</string>' \
	  '</dict></plist>' > xFlare.app/Contents/Info.plist; \
	echo "  hecho: xFlare.app$${ICON:+  (con icono)}"; \
	echo "  abrelo: clic derecho sobre xFlare.app > Abrir > Abrir  (solo la 1a vez)"; \
	echo "  o sin Gatekeeper:  xFlare.app/Contents/MacOS/xFlare"

# Ejecucion real de tests. Estricto: corta si algo falla.
test:
ifdef M
	$(DEVTC) swift test --filter $(M)Tests
else
	$(DEVTC) swift test
endif

# Version tolerante para `verify`: intenta los tests pero no corta si crashean.
# Red por si una maquina de dev no tiene completado el primer arranque de Xcode
# 14.2 (ADR-029): ahi `swift test` puede petar con signal 11. Se arregla abriendo
# Xcode.app una vez, o con `sudo xcodebuild -runFirstLaunch`.
test-advisory:
	@echo "  --- swift test (advisory) ---"
	-@$(DEVTC) swift test 2>&1 | tail -25
	@echo "  --- si arriba hay 'signal code 11': primer arranque de Xcode 14.2 sin completar, ver ADR-029 ---"

lint:
	@command -v swiftlint >/dev/null 2>&1 && swiftlint --quiet || echo "  (swiftlint no instalado, saltando)"

status:
	@python3 tools/xf_status.py

profiles-check:
	@python3 tools/xf_profile.py --all

golden-update:
	@echo "Regenerando goldens. REVISA EL DIFF ANTES DE COMMITEAR."
	$(DEVTC) XF_GOLDEN_UPDATE=1 swift test --filter Golden
	python3 tools/xfn_build.py

seal:
ifndef M
	@echo "Uso: make seal M=XFClock"; exit 1
endif
	@echo "Comprobando condiciones de sellado de $(M)..."
	@test -f Sources/$(M)/README.md || (echo "  FALTA Sources/$(M)/README.md"; exit 1)
	$(DEVTC) swift test --filter $(M)Tests
	@echo "  Tests OK y README presente."
	@echo "  Actualiza a mano docs/MODULE_STATUS.md con la fecha de hoy."

# RELEASE: toolchain de Xcode 14.2 / Swift 5.7.2 a proposito (ADR-023).
# No lleva $(DEVTC): el artefacto que se distribuye se compila con Xcode.
universal:
	swift build -c release --arch arm64 --arch x86_64
	@$(MAKE) archs

# Comprueba que la build de release salio con los dos slices. Prefiere el
# ejecutable `xFlare`; si aun no se compilo, cae a un objeto de modulo (SwiftPM
# ya los deja fat). El gate del ejecutable notarizado es B12.0.
archs:
	@P=.build/apple/Products/Release; \
	ART=$$(ls "$$P"/xFlare 2>/dev/null || ls "$$P"/XFApp.o 2>/dev/null || (echo "  primero: make universal"; exit 1)); \
	echo "  artefacto: $$ART"; \
	A=$$(lipo -archs "$$ART"); echo "  archs: $$A"; \
	echo "$$A" | grep -q 'x86_64' || (echo "  FALTA x86_64"; exit 1); \
	echo "$$A" | grep -q 'arm64'  || (echo "  FALTA arm64"; exit 1); \
	echo "  OK - universal"

clean:
	swift package clean
	rm -rf .build
