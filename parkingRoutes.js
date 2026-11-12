const express = require('express');
const router = express.Router();
const parkingController = require('../controllers/parkingController');

router.get('/capacity', parkingController.getCapacity);
router.get('/logs', parkingController.getLogs);
router.get('/summary/daily', parkingController.getDailySummary);
router.get('/summary/weekly', parkingController.getWeeklySummary);
router.get('/summary/monthly', parkingController.getMonthlySummary);
router.get('/summary/yearly', parkingController.getYearlySummary);
router.get('/summary/all-daily', parkingController.getAllDailySummaries);

router.post('/checkin', parkingController.checkIn);
router.put('/checkout/:id', parkingController.checkOut);
router.put('/update-log/:id', parkingController.updateLog);
router.post('/login', parkingController.adminLogin);

module.exports = router;
