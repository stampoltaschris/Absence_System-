require('dotenv').config();

/**
 * Ενιαίο JWT secret για sign + verify σε όλο το backend.
 * Αν λείπει το JWT_SECRET στο .env, όλα τα αρχεία χρησιμοποιούν το ίδιο fallback.
 */
const JWT_SECRET =
  process.env.JWT_SECRET || 'super_secret_school_jwt_key_2026';

module.exports = { JWT_SECRET };
