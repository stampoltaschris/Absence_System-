const jwt = require('jsonwebtoken');
require('dotenv').config();

// 🔒 Χρήση του JWT Secret από το .env (με fallback ίδιο σε όλα τα αρχεία)
const JWT_SECRET = process.env.JWT_SECRET || 'super_secret_school_jwt_key_2026';

const authenticateToken = (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1]; // Bearer TOKEN

  if (!token) {
    return res.status(401).json({ message: 'Δεν παρέχεται token αυθεντικοποίησης' });
  }

  jwt.verify(token, JWT_SECRET, (err, user) => {
    if (err) {
      console.log("❌ [AUTH ERROR]: Αποτυχία επαλήθευσης JWT Token:", err.message);
      return res.status(403).json({ message: 'Μη έγκυρο ή ληγμένο token' });
    }
    req.user = user;
    next();
  });
};

module.exports = authenticateToken;