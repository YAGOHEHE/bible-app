# Solicitud de licencia RVR1960 (borrador)

**Para:** licensing@americanbible.org
**Asunto:** Permission request: Reina-Valera 1960 full text in a free, offline Bible-reading app (non-commercial)

Antes de enviar, rellena todos los campos entre `[corchetes]`. También puedes usar el formulario web de la ABS ("Permission Request Form") y pegar este texto.

---

Dear American Bible Society Licensing Team,

I am writing to request permission to include the full text of the **Reina-Valera 1960®** in a Bible-reading application that I am developing.

**Applicant**
- Name: [Nombre y apellidos]
- Organization / church: [Nombre de la iglesia u organización, ciudad, país]
- Role: [p. ej. voluntario / desarrollador de la iglesia]
- Email / phone: [email] / [teléfono]

**Product**
- Name: [Nombre de la app] (working title)
- Platform: macOS desktop application (macOS 14 and later)
- Description: a reading and study app with chapter reading, side-by-side comparison of several translations (Spanish, Chinese, and English), keyword search, and a Strong's Greek/Hebrew lexicon linked to the KJV. The other texts it includes are in the public domain (Reina-Valera 1909, Chinese Union Version, KJV, and ASV).

**Requested use**
- Portion: the complete text of the Old and New Testaments (100%), including section headings and paragraph and poetry formatting if they are available.
- Medium: the text is stored in the application's local database and displayed on screen. The app works entirely offline: it has no user accounts, no network access, and no telemetry. The text cannot be exported as a whole; users can copy individual verses or passages.
- Format we would like to receive: USFM, USX, or any structured format you provide.

**Distribution and income**
- Price: free of charge. The app has no advertising, in-app purchases, subscriptions, or donations requests. [Ajusta si cambia]
- Distribution: [p. ej. distribuida directamente a los miembros de nuestra iglesia / ampliar a App Store en el futuro]
- Estimated users: [número aproximado] in the first year.
- Purpose: to help our congregation read and study Scripture in Spanish, Chinese, and English. [Ajusta]

**Copyright notices**
We will display the following notices:
- On every screen that shows RVR1960 text: "Citas bíblicas tomadas de la Reina-Valera 1960."
- On the app's About / Credits screen and on its download or store page: "Texto bíblico: Reina-Valera 1960® © Sociedades Bíblicas en América Latina, 1960. Renovado © Sociedades Bíblicas Unidas, 1988. Utilizado con permiso. Reina-Valera 1960® es una marca registrada de Sociedades Bíblicas Unidas, y se puede usar solamente bajo licencia."

We are happy to follow any other wording, placement, or technical requirements you specify, such as text-protection measures or usage reporting.

Could you please tell us:
1. whether this use can be licensed, and under what terms and fees;
2. whether a separate agreement would be needed if we later publish the app on the Mac App Store or on iOS;
3. whether we could obtain the text through you, or whether we should use API.Bible (and whether API.Bible allows the text to be stored for offline use).

Thank you for your time and for your work making Scripture available.

Kind regards,
[Nombre]
[Organización]
[Email · teléfono]

---

## Notas (no enviar)

- **Por qué en inglés:** la ABS está en EE. UU. Si prefieres, puedes enviarlo en español; atienden a Latinoamérica.
- **No lo presentes como comercial si no lo es.** Hoy, según `replica/architecture.md`, la app es gratis y se distribuye a la iglesia sin App Store. Si eso cambia, avísalo en la solicitud: el acuerdo comercial es distinto.
- **Al 100 % del texto no se le aplica el uso libre** (máximo 500 versículos, y las apps siempre requieren permiso por escrito). Pueden pedir regalías o un anticipo.
- **"No se puede exportar entero":** hoy no hay botón de exportar, pero `bible.sqlite` va dentro del paquete `.app` y sin cifrar. Es probable que pidan protegerlo, por ejemplo cifrando la tabla de la RVR1960. Pregúntalo antes de prometer nada.
- **Guarda la respuesta por escrito** en `data/SOURCES.md` cuando llegue.
