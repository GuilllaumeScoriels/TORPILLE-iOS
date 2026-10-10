const admin = require("firebase-admin");

admin.initializeApp();

const applyChanges = process.argv.includes("--apply");
const bucketArgument = process.argv.find((value) => value.startsWith("--bucket="));
const bucketName = bucketArgument ? bucketArgument.slice("--bucket=".length) : undefined;
const db = admin.firestore();
const bucket = admin.storage().bucket(bucketName);

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

async function allAuthUsers() {
  const usersByUid = new Map();
  const uidsByEmail = new Map();
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const user of page.users) {
      usersByUid.set(user.uid, user);
      const email = normalizeEmail(user.email);
      if (email) uidsByEmail.set(email, user.uid);
    }
    pageToken = page.pageToken;
  } while (pageToken);
  return {usersByUid, uidsByEmail};
}

async function main() {
  const [{usersByUid, uidsByEmail}, snapshot] = await Promise.all([
    allAuthUsers(),
    db.collection("users").get(),
  ]);
  const groups = new Map();
  for (const document of snapshot.docs) {
    const email = normalizeEmail(document.data().emailNormalized || document.data().email);
    if (!email) continue;
    const documents = groups.get(email) || [];
    documents.push(document);
    groups.set(email, documents);
  }

  const staleDocuments = [];
  for (const [email, documents] of groups) {
    if (documents.length < 2) continue;
    const activeUid = uidsByEmail.get(email);
    console.log(`DUPLICATE ${email}: ${documents.map((document) => document.id).join(", ")} active=${activeUid || "none"}`);
    for (const document of documents) {
      // Never delete a Firestore profile backed by an existing Auth account,
      // even if the Auth project's email-uniqueness setting has been relaxed.
      if (document.id === activeUid || usersByUid.has(document.id)) continue;
      staleDocuments.push({email, document});
    }
  }

  for (const {email, document} of staleDocuments) {
    console.log(`${applyChanges ? "DELETE" : "WOULD DELETE"} users/${document.id} (${email})`);
    if (!applyChanges) continue;
    await bucket.deleteFiles({prefix: `users/${document.id}/profile/`, force: true});
    await db.recursiveDelete(document.ref);
  }
  console.log(`${staleDocuments.length} stale duplicate user document(s) selected.`);
  if (!applyChanges) console.log("Dry run only. Re-run with --apply after reviewing this list.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
