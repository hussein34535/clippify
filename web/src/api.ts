import axios from 'axios';

const baseURL = import.meta.env.VITE_API_URL || 'http://localhost:8000';

export const API_BASE = baseURL;

export const api = axios.create({
  baseURL,
  timeout: 60000,
  headers: { 'Content-Type': 'application/json' },
});

export const streamUrl = (path: string): string =>
  `${baseURL}/api/video-stream?path=${encodeURIComponent(path)}`;
