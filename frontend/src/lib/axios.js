import axios from "axios";

export const axiosInstance = axios.create({
  baseURL: import.meta.env.MODE === "production" ? "https://chat-app-yd41.onrender.com/api" : "/api",
  // baseURL: import.meta.env.MODE === "development" ? "http://localhost:5001/api" : "/api",
  withCredentials: true,
});
