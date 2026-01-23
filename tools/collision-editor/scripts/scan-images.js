import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Get __dirname equivalent in ESM
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Adjust paths - we are in /scripts/, assets are linked in /public/project-assets/
const assetsDir = path.resolve(__dirname, '../public/project-assets/img');
const outputFile = path.resolve(__dirname, '../public/image-list.json');

console.log(`Scanning for images in: ${assetsDir}`);

function walkSync(dir, filelist = []) {
    const files = fs.readdirSync(dir);
    files.forEach(function (file) {
        const filePath = path.join(dir, file);
        if (fs.statSync(filePath).isDirectory()) {
            filelist = walkSync(filePath, filelist);
        } else {
            if (/\.(png|jpe?g|gif|webp)$/i.test(file)) {
                // Get relative path from assetsDir
                const relPath = path.relative(assetsDir, filePath);
                filelist.push({
                    name: relPath,
                    path: `/project-assets/img/${relPath}`
                });
            }
        }
    });
    return filelist;
}

try {
    if (!fs.existsSync(assetsDir)) {
        console.error(`Directory not found: ${assetsDir}`);
        fs.writeFileSync(outputFile, JSON.stringify([], null, 2));
        process.exit(0);
    }

    const images = walkSync(assetsDir);

    fs.writeFileSync(outputFile, JSON.stringify(images, null, 2));
    console.log(`Generated list with ${images.length} images (recursive) at ${outputFile}`);

} catch (err) {
    console.error('Error scanning images:', err);
    process.exit(1);
}
