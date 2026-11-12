const mysql = require('mysql2');
const dotenv = require('dotenv');
const path = require('path');
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const pool = mysql.createPool({
    host: process.env.DB_HOST || '192.168.111.101',
    port: Number(process.env.DB_PORT) || 3306,
    user: process.env.DB_USER || 'parking_app',
    password: process.env.DB_PASSWORD || 'Admin@123',
    database: process.env.DB_NAME || 'parking_db',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
    timezone: '+07:00',
    dateStrings: true
});

module.exports = pool.promise();
