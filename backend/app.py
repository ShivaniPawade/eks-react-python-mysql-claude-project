from flask import Flask, jsonify, request
from flask_cors import CORS
import mysql.connector
import os


app = Flask(__name__)
CORS(app)

def get_db():
    return mysql.connector.connect(
        host=os.environ["DB_HOST"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASSWORD"],
        database=os.environ["DB_NAME"]
    )

def init_db():
    conn = get_db()
    cur = conn.cursor()
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            email VARCHAR(100) NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    cur.close()
    conn.close()

@app.route("/health")
def health():
    return jsonify({"status": "ok"})

@app.route("/api/users", methods=["GET"])
def get_users():
    conn = get_db()
    cur = conn.cursor(dictionary=True)
    cur.execute("SELECT * FROM users ORDER BY created_at DESC")
    users = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify(users)

@app.route("/api/users", methods=["POST"])
def create_user():
    data = request.json
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO users (name, email) VALUES (%s, %s)",
        (data["name"], data["email"])
    )
    conn.commit()
    new_id = cur.lastrowid
    cur.close()
    conn.close()
    return jsonify({"id": new_id, "name": data["name"], "email": data["email"]}), 201

@app.route("/api/users/<int:user_id>", methods=["DELETE"])
def delete_user(user_id):
    conn = get_db()
    cur = conn.cursor()
    cur.execute("DELETE FROM users WHERE id = %s", (user_id,))
    conn.commit()
    cur.close()
    conn.close()
    return jsonify({"deleted": user_id})

if __name__ == "__main__":
    init_db()
    app.run(host="0.0.0.0", port=5000)
