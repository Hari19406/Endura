def calculate_fatigue(rpe, sleep_hours, previous_load):
    fatigue = 0

    # RPE impact
    fatigue += rpe * 5

    # Sleep impact (less sleep = more fatigue)
    if sleep_hours < 6:
        fatigue += (6 - sleep_hours) * 5

    # Training load impact
    fatigue += previous_load * 2

    # Normalize (0–100)
    return min(fatigue, 100)


# Example
print(calculate_fatigue(rpe=7, sleep_hours=5, previous_load=3))
