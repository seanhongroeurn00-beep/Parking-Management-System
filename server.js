const express = require('express');
const cors = require('cors');
const parkingRoutes = require('./routes/parkingRoutes');

const app = express();

// បើកសិទ្ធិ CORS ឲ្យគ្រប់ IP ទាំងអស់ (ដើម្បីកុំឲ្យស្ទះពេល Login)
app.use(cors({
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization']
}));

app.use(express.json());

// Set Routes
app.use('/api/parking', parkingRoutes);

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => {
    console.log(`Server running on port ${PORT}`);
});
