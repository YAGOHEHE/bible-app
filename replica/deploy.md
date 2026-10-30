# Preflight de publicación — Biblia 1.1.2 (macOS 14+)

Fecha: 2026-10-31 · Método: skill replica-deploy (adaptada a app de macOS) · **Solo evaluación: no se ha publicado nada.**

## Veredicto
**Todavía no se puede subir a la Mac App Store**, pero no por la calidad de la app ni por el contenido principal:
los tests, la paridad (must 100 %) y la limpieza del binario pasan. Faltan **requisitos de publicación** que no existen
en una distribución ad-hoc para un grupo, y hay **un riesgo de derechos** que conviene cerrar antes.
Con 1–2 días de trabajo + la cuenta de desarrollador, es publicable.

## 1. Comprobaciones automáticas (replica-deploy, paso 1)
| Comprobación | Resultado |
|---|---|
| Tests (`swift test`, en lugar de playwright) | ✅ 200 tests en verde |
| Paridad (`parity.py replica/features.csv`) | ✅ 77,7/100 · must 25/25 (100 %) |
| Restos del original (`sweep.py . --config replica/brand.json`) | ⚠️ 7 coincidencias, **ninguna en la app**: 4 falsos positivos («ct_Synthetic**Bol**d» en artefactos de GRDB dentro de `App/.build`) y 3 en `data/SOURCES.md` (frase «No data from /Applications/精读圣经.app … was used»). Reescribir esa frase sin el nombre. `strings` del binario: sin «jdbible», «christapps» ni «精读». |
| Ficha de tienda (`listing.py replica/launch/listing.json`, borrador) | ✅ 0 errores · 1 aviso: «biblia» repetida en keywords |
| Build de producción (`scripts/make_app.sh`) | ✅ compila; firma **ad-hoc** |

## 2. Comprobaciones manuales
| Comprobación | Resultado |
|---|---|
| Bugs S1/S2 abiertos | ✅ ninguno (`replica/bugs.md`: todos «Arreglado» o «No reproducible») |
| Clics reales (barra, selección acumulativa, menú contextual, notas) | ✅ verificados con eventos reales (v1.1.1–1.1.2) |
| Política de privacidad y página de soporte | ❌ **no existen** — la App Store las exige (URL) aunque la app no recoja datos |
| Datos recogidos | ✅ ninguno: sin red (no hay URLSession), sin cuentas, sin analítica → etiqueta «No se recopilan datos» |
| Atribuciones de contenido | ✅ «Acerca de» lista licencias; OpenBible CC BY 4.0 con enlace |
| Nombre propio | ❌ «Biblia» es genérico y casi seguro **ya está ocupado** en la App Store (los nombres deben ser únicos); además débil para destacar |
| Icono, títulos propios | ✅ cruz latina propia, nada del original |

## 3. Requisitos técnicos de la Mac App Store (paso 5)
| Requisito | Estado | Qué hacer |
|---|---|---|
| Apple Developer Program (99 USD/año) | ❌ | Darse de alta (lo hace el usuario) |
| Firma de distribución (Apple Distribution + Mac Installer) y perfil | ❌ ad-hoc | Certificados en developer.apple.com; firmar con `codesign` y empaquetar con `productbuild --sign` (viable sin Xcode) |
| App Sandbox (`com.apple.security.app-sandbox`) | ❌ sin entitlements | Añadir entitlements; la app ya no usa red ni archivos fuera de su carpeta, así que solo hace falta sandbox. Los datos pasan a `~/Library/Containers/org.biblia.lector/`; `LegacyMigration` (lee otro dominio) dejaría de funcionar dentro del sandbox — en la versión de tienda se puede quitar |
| Hardened Runtime | ❌ | `codesign --options runtime` |
| Subida | ❌ | App **Transporter** (gratis, Mac App Store) o `xcrun altool`/`notarytool` |
| Ficha | 🟡 borrador | Capturas 1280×800 o 2880×1800, categoría Referencia, edad 4+, gratis, URL de privacidad y soporte |

Alternativa sin App Store pero pública: **web + DMG con Developer ID y notarización** (misma cuenta de 99 USD): se abre sin avisos.

## 4. Riesgos de revisión y legales
1. **新标点和合本 (CUV y CUVT)** — el texto de 1919 es de dominio público, pero la **puntuación nueva de 1988/89** la
   publica la Sociedad Bíblica de Hong Kong/UBS, que reclama derechos. Nuestra única base es la declaración de dominio
   público de eBible.org. **Riesgo real** en una tienda comercial y mundial (y la versión china es central para el grupo).
   Opciones: (a) escribir a la Hong Kong Bible Society para confirmar/licenciar; (b) usar el texto de 1919 con la
   puntuación original (si se encuentra una fuente libre fiable); (c) mantenerlo y asumir el riesgo con la atribución.
2. **Guía 4.3 (spam/duplicados)** — hay muchísimas apps de Biblia. Lo diferencial (chino + español + inglés en paralelo,
   glosas, Strong, sin conexión ni cuentas) debe verse claro en el nombre, el subtítulo y las capturas.
3. **Guía 4.1 (copycat)** — ✅ clean-room: nada del original en código, binario, nombre ni icono.
4. **KJV en Reino Unido** — patente de la Corona sobre la *impresión*; en apps digitales se considera bajo riesgo
   (muchas apps lo incluyen). Opcional: excluir el Reino Unido o consultarlo.
5. **RVR1960** — `replica/solicitud-licencia-rvr1960.md` es solo un borrador: la RVR1960 **no** está incluida; no
   añadirla sin la licencia firmada de la ABS/SBU.
6. **BLM (Santa Biblia libre para el mundo)** — dominio público según HelloAO/eBible; conviene guardar captura de la
   declaración de eBible como prueba.

## 5. Lo que falta, en orden
1. Elegir **nombre único** (replica-brand) y comprobar disponibilidad en App Store Connect.
2. Resolver el punto 4.1 (**puntuación del 和合本**).
3. Publicar **política de privacidad y soporte** (p. ej. una página en GitHub Pages: «No recogemos datos…» + contacto).
4. Cuenta **Apple Developer**; sandbox + hardened runtime + firma de distribución en `scripts/make_app.sh` (variante `make_appstore.sh`).
5. Ficha final con **capturas** (replica-launch) y quitar «biblia» repetida de keywords.
6. Reescribir la frase de `data/SOURCES.md` para que el barrido quede limpio (y excluir `App/.build`).
7. Beta con **TestFlight para Mac** al grupo, después revisión.

**Biblia Clásica (10.13+)**: su build incrusta librerías de Swift y un SQLite propio y no está probada en un Mac
antiguo real; antes de plantear la tienda (habría que comprobar qué versión mínima de macOS acepta hoy App Store
Connect), lo razonable es **web + DMG con Developer ID notarizado**.
