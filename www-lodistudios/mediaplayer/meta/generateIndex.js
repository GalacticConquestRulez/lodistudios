const fs = require("fs");
const path = require("path");

const metaDir = __dirname;
const indexPath = path.join(metaDir, "index.json");

fs.readdir(metaDir, (err, files) => {
  if (err) {
    console.error("Failed to read meta directory:", err);
    return;
  }

  const jsonFiles = files.filter(f => f.endsWith(".json") && f !== "index.json");

  const metadataList = jsonFiles.map(filename => {
    const filePath = path.join(metaDir, filename);
    const rawData = fs.readFileSync(filePath);
    try {
      return JSON.parse(rawData);
    } catch (err) {
      console.error(`Failed to parse ${filename}:`, err);
      return null;
    }
  }).filter(Boolean); // Remove null entries

  fs.writeFileSync(indexPath, JSON.stringify(metadataList, null, 2));
  console.log(`✅ index.json created with ${metadataList.length} songs.`);
});
