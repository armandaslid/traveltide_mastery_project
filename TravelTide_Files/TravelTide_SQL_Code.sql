WITH session_based AS
(
SELECT	s.session_id
	,s.user_id
        ,s.trip_id
        ,s.session_start
        ,s.session_end
        ,s.flight_discount
        ,s.hotel_discount
        ,s.flight_discount_amount
        ,s.hotel_discount_amount
        ,s.flight_booked
        ,s.hotel_booked
        ,s.page_clicks
        ,s.cancellation
        ,EXTRACT (EPOCH FROM (s.session_end-s.session_start)) AS session_duration
        ,f.origin_airport
        ,f.destination
        ,f.destination_airport
        ,f.seats
        ,f.return_flight_booked
        ,f.departure_time
        ,f.return_time
        ,f.checked_bags
        ,f.trip_airline
        ,f.destination_airport_lat
        ,f.destination_airport_lon
        ,f.base_fare_usd
        ,h.hotel_name
        ,CASE WHEN h.nights < 0 THEN 1 ELSE h.nights END AS nights
        ,h.rooms
        ,h.check_in_time
        ,h.check_out_time
        ,h.hotel_per_room_usd AS hotel_price_per_room_night_usd
        ,u.home_airport_lat
        ,u.home_airport_lon
FROM sessions s
LEFT JOIN users u ON s.user_id = u.user_id
LEFT JOIN flights f ON s.trip_id = f.trip_id
LEFT JOIN hotels h ON s.trip_id = h.trip_id
WHERE s.user_id IN (SELECT	user_id
                    FROM sessions
                    WHERE session_start > '2023-01-04'
                    GROUP BY user_id
                    HAVING COUNT(*) > 7)
),

user_based AS
(
SELECT	user_id
	,SUM(page_clicks) AS num_clicks
        ,COUNT(distinct session_id) AS num_sessions
        ,ROUND(AVG(session_duration), 2) AS avg_session_duration
	,(SUM(CASE WHEN flight_booked OR hotel_booked THEN 1 ELSE 0 END)::FLOAT / COUNT(session_id)) * 100 AS booking_rate
	,(SUM(CASE WHEN cancellation THEN 1 ELSE 0 END)::FLOAT / COUNT(session_id)) * 100 AS cancellation_rate
	,ROUND(AVG(page_clicks), 2) AS avg_clicks_per_session
				
FROM session_based
GROUP BY user_id
),

trip_based AS
(
SELECT	user_id
	,COUNT(trip_id) AS num_trips
        ,SUM(CASE WHEN flight_booked AND return_flight_booked THEN 2
             			WHEN flight_booked THEN 1
             			ELSE 0
             END) AS num_flights
	,SUM((hotel_price_per_room_night_usd * nights * rooms) * (1 - COALESCE(hotel_discount_amount, 0))) AS money_spent_hotel
        ,ROUND(AVG(EXTRACT(DAY FROM departure_time - session_end)), 0) AS avg_days_before_trip
        ,ROUND(AVG(HAVERSINE_DISTANCE(home_airport_lat, home_airport_lon, destination_airport_lat, destination_airport_lon))::NUMERIC, 0) AS avg_km_flown
	,SUM(base_fare_usd * (1 - COALESCE(flight_discount_amount, 0))) AS money_spent_flight
	,(SUM((base_fare_usd * (1 - COALESCE(flight_discount_amount, 0)))
              +
              (hotel_price_per_room_night_usd * nights * rooms * (1 - COALESCE(hotel_discount_amount, 0))))
          	/
          	NULLIF(COUNT(trip_id), 0)) AS avg_spending_per_trip
	,ABS(ROUND(AVG(EXTRACT(EPOCH FROM (check_out_time - check_in_time)) / 86400), 0)) AS avg_trip_duration_days
	,(SUM(CASE WHEN flight_booked AND hotel_booked THEN 1 ELSE 0 END)::FLOAT / COUNT(trip_id)) * 100 AS flight_hotel_combo_rate
	,ROUND(AVG(seats), 0) AS avg_seats_per_flight
	,(SUM(CASE WHEN flight_discount OR hotel_discount THEN 1 ELSE 0 END)::FLOAT / COUNT(trip_id)) * 100 AS discount_utilization_rate
	,AVG(flight_discount_amount) AS avg_flight_discount
	,MAX(HAVERSINE_DISTANCE(home_airport_lat, home_airport_lon, destination_airport_lat, destination_airport_lon)) AS max_distance_traveled
	
FROM session_based
WHERE trip_id IS NOT NULL AND trip_id NOT IN (SELECT DISTINCT trip_id
                                              FROM session_based
                                              WHERE cancellation)
GROUP BY user_id
)

SELECT	ub.*
	,EXTRACT(YEAR FROM age(now(), u.birthdate)) AS age
        ,u.gender
        ,u.married
        ,u.has_children
        ,u.home_country
        ,u.home_city
        ,EXTRACT(YEAR FROM age(now(), u.sign_up_date)) as years_spent_on_traveltide
        ,tb.*
FROM users u
JOIN user_based ub ON u.user_id = ub.user_id
JOIN trip_based tb ON u.user_id = tb.user_id
;
