// tools/import_municipios.js
// Ejecuta: node tools/import_municipios.js

import admin from 'firebase-admin';
import fs from 'fs';

// ✅ Asegúrate de tener el JSON de credenciales del service account
// y haber configurado la variable:
// export GOOGLE_APPLICATION_CREDENTIALS="ruta/a/serviceAccountKey.json"

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
});

const db = admin.firestore();

async function importarMunicipios() {
  const data = JSON.parse(fs.readFileSync("tools/municipios.json", "utf-8"));
  const col = db.collection('municipios');

  let batch = db.batch();
  let count = 0;
  let total = 0;

  for (const m of data) {
    const ref = col.doc(m.id);
    batch.set(ref, m, { merge: true });
    count++;
    total++;
    if (count === 500) {
      await batch.commit();
      batch = db.batch();
      count = 0;
    }
  }

  if (count) await batch.commit();
  console.log(`✅ Importados ${total} municipios`);
}

importarMunicipios().catch(console.error);
