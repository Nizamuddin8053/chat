import { v2 as cloudinary } from "cloudinary";

import { config } from "dotenv";
import path from "path";

// Load .env from project root (one level up from backend directory)
config({ path: path.resolve(process.cwd(), "../.env") });

cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

export default cloudinary;
