import firebase_admin
from firebase_admin import credentials, firestore
import json
import pandas as pd
import os

# Initialize Firebase Admin SDK
cred = credentials.Certificate("fypp-f0b63-firebase-adminsdk-fbsvc-e0c249ef89.json")  # Your key filename
firebase_admin.initialize_app(cred)
db = firestore.client()

# Output folder for individual JSON sessions
os.makedirs("json_sessions", exist_ok=True)

all_rows = []

# Get all users
users_ref = db.collection("users")
user_docs = users_ref.stream()

print("Starting export of walking patterns...")

for user_doc in user_docs:
    user_id = user_doc.id
    print(f"Processing user: {user_id}")

    walking_patterns_ref = users_ref.document(user_id).collection("walking_patterns")
    sessions = walking_patterns_ref.stream()

    for session_doc in sessions:
        session = session_doc.to_dict()
        session_id = session.get("sessionId", session_doc.id)
        data = session.get("data", [])

        # Save individual session JSON file
        json_path = f"json_sessions/{user_id}_{session_id}.json"
        with open(json_path, "w") as json_file:
            json.dump(data, json_file, indent=2)

        # Prepare flattened data for CSV
        for entry in data:
            all_rows.append({
                "userId": user_id,
                "sessionId": session_id,
                "timestamp": entry.get("timestamp"),
                "accel_x": entry["accel"]["x"],
                "accel_y": entry["accel"]["y"],
                "accel_z": entry["accel"]["z"],
                "gyro_x": entry["gyro"]["x"],
                "gyro_y": entry["gyro"]["y"],
                "gyro_z": entry["gyro"]["z"],
            })

print(f"Saving combined CSV with {len(all_rows)} rows...")
df = pd.DataFrame(all_rows)
df.to_csv("walking_patterns_combined.csv", index=False)

print("Export completed successfully!")
print(f"Individual JSON files saved in folder: json_sessions")
print("Combined CSV saved as: walking_patterns_combined.csv")
