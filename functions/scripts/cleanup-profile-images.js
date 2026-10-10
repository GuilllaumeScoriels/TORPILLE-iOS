const admin = require("firebase-admin");

admin.initializeApp();

const applyChanges = process.argv.includes("--apply");
const bucketArgument = process.argv.find((value) => value.startsWith("--bucket="));
const bucketName = bucketArgument ? bucketArgument.slice("--bucket=".length) : undefined;
const db = admin.firestore();
const bucket = admin.storage().bucket(bucketName);

function storagePathFromUrl(rawUrl) {
  if (typeof rawUrl !== "string" || !rawUrl) return null;
  if (rawUrl.startsWith("gs://")) {
    const withoutScheme = rawUrl.slice(5);
    const slash = withoutScheme.indexOf("/");
    return slash > 0 ? withoutScheme.slice(slash + 1) : null;
  }
  try {
    const parsed = new URL(rawUrl);
    const match = parsed.pathname.match(/\/b\/[^/]+\/o\/(.+)$/);
    return match ? decodeURIComponent(match[1]) : null;
  } catch (_) {
    return null;
  }
}

async function allAuthUids() {
  const result = new Set();
  let pageToken;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    page.users.forEach((user) => result.add(user.uid));
    pageToken = page.pageToken;
  } while (pageToken);
  return result;
}

async function main() {
  const [authUids, userSnapshot, filesResult] = await Promise.all([
    allAuthUids(),
    db.collection("users").get(),
    bucket.getFiles({prefix: "users/"}),
  ]);
  const profiles = new Map(userSnapshot.docs.map((document) => [document.id, document.data()]));
  const files = filesResult[0];
  const deletions = [];

  for (const file of files) {
    const match = file.name.match(/^users\/([^/]+)\/profile\/([^/]+)$/);
    if (!match) continue;
    const uid = match[1];
    const profile = profiles.get(uid);
    const referencedPath = storagePathFromUrl(profile && profile.photoUrl);
    const accountMissing = !authUids.has(uid) || !profile;
    const superseded = !accountMissing && file.name !== referencedPath;
    if (accountMissing || superseded) {
      deletions.push({file, reason: accountMissing ? "missing-user" : "superseded"});
    }
  }

  deletions.forEach(({file, reason}) => console.log(`${applyChanges ? "DELETE" : "WOULD DELETE"} ${file.name} (${reason})`));
  console.log(`${deletions.length} profile image(s) selected in bucket ${bucket.name}.`);
  if (!applyChanges) {
    console.log("Dry run only. Re-run with --apply after reviewing this list.");
    return;
  }
  for (const {file} of deletions) {
    await file.delete({ignoreNotFound: true});
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
