const jwt = require('jsonwebtoken');
const { JWT_SECRET } = require('../utils/jwt_secret');

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