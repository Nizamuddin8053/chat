import express from "express";
import mongoose from "mongoose";

const router = express.Router();

// Health check endpoint
router.get("/", async (req, res) => {
  
   const dbConnected = mongoose.connection.readyState === 1;
   
   if(!dbConnected){
     return res.status(503).json({
        status: "unhealthy",
        timestamp: new Date().toISOString(),
        database: "disconnected",
        environment: process.env.NODE_ENV || "development",
     });
   }

   return res.status(200).json({
      status: "healthy",
      timestamp: new Date().toISOString(),
      database: "connected",
      environment: process.env.NODE_ENV || "development"
   });
});

export default router; 
