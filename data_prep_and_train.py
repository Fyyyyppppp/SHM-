import pandas as pd
import numpy as np
from collections import Counter
from sklearn.model_selection import train_test_split
import tensorflow as tf

SEQUENCE_LENGTH = 100
CSV_FILE = "walking_patterns_combined.csv"

# Load dataset
df = pd.read_csv(CSV_FILE)
print(f"Loaded {len(df)} rows")

# Encode userId labels
user_ids = df['userId'].unique()
user_to_label = {user: i for i, user in enumerate(user_ids)}
df['label'] = df['userId'].map(user_to_label)

# Generate sequences from sessionId
def create_sequences(df, seq_len=SEQUENCE_LENGTH):
    sequences, labels = [], []
    grouped = df.groupby('sessionId')
    for _, group in grouped:
        group = group.sort_values('timestamp')
        data = group[['accel_x', 'accel_y', 'accel_z', 'gyro_x', 'gyro_y', 'gyro_z']].values
        label = group['label'].iloc[0]
        for start in range(0, len(data) - seq_len + 1, seq_len):
            seq = data[start:start+seq_len]
            sequences.append(seq)
            labels.append(label)
    return np.array(sequences), np.array(labels)

X, y = create_sequences(df)

# Filter out users with fewer than 2 sequences
label_counts = Counter(y)
valid_labels = [label for label, count in label_counts.items() if count >= 2]
mask = np.isin(y, valid_labels)
X, y = X[mask], y[mask]

# Split dataset
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, stratify=y, random_state=42)

# LSTM model
num_classes = len(np.unique(y))
model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(SEQUENCE_LENGTH, 6)),
    tf.keras.layers.LSTM(64, return_sequences=True),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.LSTM(32),
    tf.keras.layers.Dropout(0.3),
    tf.keras.layers.Dense(32, activation='relu'),
    tf.keras.layers.Dense(num_classes, activation='softmax')
])
model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])

# Train
model.fit(X_train, y_train, epochs=30, batch_size=32, validation_split=0.2)

# Evaluate
loss, acc = model.evaluate(X_test, y_test)
print(f"Test accuracy: {acc:.4f}")

# Step 9: Convert and save model to TensorFlow Lite format (.tflite)
converter = tf.lite.TFLiteConverter.from_keras_model(model)

# 🔧 Add this to handle LSTM ops safely
converter.target_spec.supported_ops = [
    tf.lite.OpsSet.TFLITE_BUILTINS,
    tf.lite.OpsSet.SELECT_TF_OPS
]
converter._experimental_lower_tensor_list_ops = False  # ✅ important

# Optional optimizations
converter.optimizations = [tf.lite.Optimize.DEFAULT]

# Convert
tflite_model = converter.convert()

# Save model
with open("walking_pattern_lstm_model.tflite", "wb") as f:
    f.write(tflite_model)

print("✅ TFLite model saved successfully without LSTM issues.")
