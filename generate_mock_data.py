import json
import uuid
import datetime
# pyrefly: ignore [missing-import]
from sentence_transformers import SentenceTransformer

# Load the local model or download from HuggingFace
try:
    model = SentenceTransformer('all-MiniLM-L6-v2')
except Exception as e:
    print(f"Failed to load model: {e}")
    exit(1)

mock_entries = [
    {
        "source": "WhatsApp",
        "sender": "Sarah",
        "content": "The Q4 merger terms need revision by Friday."
    },
    {
        "source": "WhatsApp",
        "sender": "Mom",
        "content": "Are you coming for dinner on Sunday? I'm making lasagna."
    },
    {
        "source": "Calendar",
        "sender": "System",
        "content": "Dentist appointment at 4:30 PM tomorrow."
    },
    {
        "source": "SMS",
        "sender": "Swiggy",
        "content": "Your order is out for delivery. OTP is 1234."
    },
    {
        "source": "Slack",
        "sender": "John from Legal",
        "content": "Please confirm the liability cap before we send the contract."
    },
    {
        "source": "Gmail",
        "sender": "Priya S.",
        "content": "Subject: Q3 Design Assets Review - Please check the attached figma links."
    },
    {
        "source": "Calendar",
        "sender": "System",
        "content": "Daily Standup at 10:00 AM."
    },
    {
        "source": "WhatsApp",
        "sender": "Mike",
        "content": "Can we push the meeting to 3 PM? I'm running late."
    },
    {
        "source": "SMS",
        "sender": "Bank",
        "content": "Your account ending in 1234 was credited with $500.00."
    },
    {
        "source": "Slack",
        "sender": "DevOps Bot",
        "content": "Production deployment successful. 0 errors."
    }
]

print("Computing embeddings...")

final_data = []
now = datetime.datetime.now()

for i, entry in enumerate(mock_entries):
    text = entry["content"]
    # Compute the embedding (384 dimensions)
    embedding = model.encode(text)
    
    # Create the final record
    record = {
        "id": i + 1,
        "source": entry["source"],
        "sender": entry["sender"],
        "content": entry["content"],
        "timestamp": (now - datetime.timedelta(minutes=(10 - i) * 30)).isoformat(),
        "embedding": embedding.tolist()
    }
    final_data.append(record)

# Save to JSON
output_path = "assets/mock_data.json"
with open(output_path, "w") as f:
    json.dump(final_data, f, indent=2)

print(f"Generated {len(final_data)} mock entries with embeddings. Saved to {output_path}")
