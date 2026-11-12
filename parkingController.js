
const db = require('../config/db');

// ១. ទាញយកសមត្ថភាពចំណត
exports.getCapacity = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT * FROM parking_capacity');
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ២. ទាញយក Logs ចូល-ចេញ
exports.getLogs = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT * FROM vehicle_logs ORDER BY id DESC');
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៣. ទាញយករបាយការណ៍ប្រចាំថ្ងៃ (ថ្ងៃនេះ)
exports.getDailySummary = async (req, res) => {
    try {
        const todayKhmer = new Date().toLocaleString("sv-SE", { timeZone: "Asia/Phnom_Penh" }).split(" ")[0];
        const [rows] = await db.query(
            'SELECT DATE_FORMAT(summary_date, "%Y-%m-%d") AS summary_date, vehicle_type, total_vehicles_count, total_income FROM daily_summary WHERE summary_date = ?',
            [todayKhmer]
        );
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៤. ទាញយករបាយការណ៍ប្រចាំសប្តាហ៍
exports.getWeeklySummary = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT * FROM view_weekly_report ORDER BY report_year DESC, report_week DESC');
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៥. ទាញយករបាយការណ៍ប្រចាំខែ
exports.getMonthlySummary = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT * FROM view_monthly_report ORDER BY report_year DESC, report_month DESC');
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៦. ទាញយករបាយការណ៍ប្រចាំឆ្នាំ
exports.getYearlySummary = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT * FROM view_yearly_report ORDER BY report_year DESC');
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៧. កត់ត្រាយានយន្តចូល (Check-In)
exports.checkIn = async (req, res) => {
    let { plate_no, vehicle_type } = req.body;
    try {
        if (!plate_no || !vehicle_type) {
            return res.status(400).json({ message: 'សូមបញ្ចូលស្លាកលេខ និងប្រភេទយានយន្ត!' });
        }

        vehicle_type = vehicle_type.trim();
        if (vehicle_type.toLowerCase() === 'car') vehicle_type = 'Car';
        if (vehicle_type.toLowerCase() === 'motor') vehicle_type = 'Motor';

        const [capacity] = await db.query('SELECT available_space FROM parking_capacity WHERE vehicle_type = ?', [vehicle_type]);

        if (capacity.length === 0) {
            return res.status(400).json({ message: 'ប្រភេទយានយន្តមិនត្រឹមត្រូវ!' });
        }

        if (capacity[0].available_space <= 0) {
            return res.status(400).json({ message: `ចំណតសម្រាប់ ${vehicle_type} ពេញហើយ!` });
        }

        const localTimeIn = new Date().toLocaleString("sv-SE", { timeZone: "Asia/Phnom_Penh" });
        await db.query('INSERT INTO vehicle_logs (plate_no, vehicle_type, time_in) VALUES (?, ?, ?)', [plate_no, vehicle_type, localTimeIn]);

        res.json({ message: 'កត់ត្រាចូលចតជោគជ័យ!' });
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៨. កត់ត្រាយានយន្តចេញ (Check-Out)
exports.checkOut = async (req, res) => {
    const { id } = req.params;
    const { custom_time_out } = req.body;
    try {
        const timeOut = custom_time_out || new Date().toLocaleString("sv-SE", { timeZone: "Asia/Phnom_Penh" });
        await db.query('UPDATE vehicle_logs SET time_out = ? WHERE id = ?', [timeOut, id]);
        res.json({ message: 'កត់ត្រាចេញជោគជ័យ!' });
    } catch (error) { res.status(500).json({ error: error.message }); }
};

// ៩. កែប្រែទិន្នន័យ Log
exports.updateLog = async (req, res) => {
    const { id } = req.params;
    const { plate_no, time_in, time_out } = req.body;
    try {
        const formattedTimeOut = time_out && time_out.trim() !== "" ? time_out : null;
        await db.query('UPDATE vehicle_logs SET plate_no = ?, time_in = ?, time_out = ? WHERE id = ?', [plate_no, time_in, formattedTimeOut, id]);
        res.json({ message: 'កែប្រែទិន្នន័យជោគជ័យ!' });
    } catch (error) { res.status(500).json({ error: error.message }); }
};
// ១០. Admin Login
exports.adminLogin = async (req, res) => {
    const { username, password } = req.body;
    try {
        if (!username || !password) {
            return res.status(400).json({ message: 'សូមបញ្ចូល Username និង Password!' });
        }

        const [users] = await db.query('SELECT * FROM admin_users WHERE username = ? AND password = SHA2(?, 256)', [username, password]);

        if (users.length === 0) {
            return res.status(401).json({ message: 'Username ឬ Password មិនត្រឹមត្រូវ!' });
        }

        // កែប្រែត្រង់នេះ៖ បន្ថែម role បញ្ជូនទៅ Frontend
        res.json({
            message: 'Login ជោគជ័យ!',
            admin: {
                id: users[0].id,
                username: users[0].username,
                full_name: users[0].full_name,
                role: users[0].role || 'cashier'
            }
        });
    } catch (error) {
        res.status(500).json({ error: error.message });
    }
};
// ១១. របាយការណ៍ប្រចាំថ្ងៃទាំងអស់សម្រាប់មើលក្នុង Reports Page
exports.getAllDailySummaries = async (req, res) => {
    try {
        const [rows] = await db.query('SELECT DATE_FORMAT(summary_date, "%Y-%m-%d") AS summary_date, vehicle_type, total_vehicles_count, total_income FROM daily_summary ORDER BY summary_date DESC');
        res.json(rows);
    } catch (error) { res.status(500).json({ error: error.message }); }
};
