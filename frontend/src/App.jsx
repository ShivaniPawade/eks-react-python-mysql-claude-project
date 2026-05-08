import { useState, useEffect } from "react";

const API = process.env.REACT_APP_API_URL || "";

export default function App() {
  const [users, setUsers] = useState([]);
  const [form, setForm] = useState({ name: "", email: "" });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => { fetchUsers(); }, []);

  async function fetchUsers() {
    try {
      const res = await fetch(`${API}/api/users`);
      const data = await res.json();
      setUsers(data);
    } catch {
      console.log("API URL:", API);
      setError("Cannot reach backend");
    }
  }

  async function addUser(e) {
    e.preventDefault();
    if (!form.name || !form.email) return;
    setLoading(true);
    try {
      await fetch(`${API}/api/users`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(form),
      });
      setForm({ name: "", email: "" });
      fetchUsers();
    } catch {
      setError("Failed to add user");
    }
    setLoading(false);
  }

  async function deleteUser(id) {
    await fetch(`${API}/api/users/${id}`, { method: "DELETE" });
    fetchUsers();
  }

  return (
    <div style={{ maxWidth: 700, margin: "40px auto", fontFamily: "sans-serif", padding: "0 20px" }}>
      <h1 style={{ fontSize: 24, marginBottom: 4 }}>3-Tier EKS App</h1>
      <p style={{ color: "#666", fontSize: 14, marginBottom: 32 }}>
        React → Python/Flask → MySQL RDS
      </p>

      {/* Add User Form */}
      <div style={{ background: "#f8f9fa", borderRadius: 8, padding: 20, marginBottom: 32 }}>
        <h2 style={{ fontSize: 16, marginBottom: 16 }}>Add User</h2>
        <form onSubmit={addUser} style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
          <input
            placeholder="Name"
            value={form.name}
            onChange={e => setForm({ ...form, name: e.target.value })}
            style={{ flex: 1, minWidth: 140, padding: "8px 12px", borderRadius: 6, border: "1px solid #ddd", fontSize: 14 }}
          />
          <input
            placeholder="Email"
            type="email"
            value={form.email}
            onChange={e => setForm({ ...form, email: e.target.value })}
            style={{ flex: 2, minWidth: 180, padding: "8px 12px", borderRadius: 6, border: "1px solid #ddd", fontSize: 14 }}
          />
          <button
            type="submit"
            disabled={loading}
            style={{ padding: "8px 20px", background: "#5c4bde", color: "#fff", border: "none", borderRadius: 6, cursor: "pointer", fontSize: 14 }}
          >
            {loading ? "Adding..." : "Add"}
          </button>
        </form>
      </div>

      {/* Error */}
      {error && (
        <div style={{ background: "#fff0f0", border: "1px solid #fcc", borderRadius: 6, padding: "10px 14px", marginBottom: 16, color: "#c00", fontSize: 14 }}>
          {error}
        </div>
      )}

      {/* Users Table */}
      <h2 style={{ fontSize: 16, marginBottom: 12 }}>Users ({users.length})</h2>
      {users.length === 0 ? (
        <p style={{ color: "#999", fontSize: 14 }}>No users yet. Add one above.</p>
      ) : (
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
          <thead>
            <tr style={{ borderBottom: "2px solid #eee" }}>
              <th style={{ textAlign: "left", padding: "8px 10px", color: "#666" }}>ID</th>
              <th style={{ textAlign: "left", padding: "8px 10px", color: "#666" }}>Name</th>
              <th style={{ textAlign: "left", padding: "8px 10px", color: "#666" }}>Email</th>
              <th style={{ textAlign: "left", padding: "8px 10px", color: "#666" }}>Created</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {users.map(u => (
              <tr key={u.id} style={{ borderBottom: "1px solid #f0f0f0" }}>
                <td style={{ padding: "10px 10px", color: "#999" }}>{u.id}</td>
                <td style={{ padding: "10px 10px", fontWeight: 500 }}>{u.name}</td>
                <td style={{ padding: "10px 10px" }}>{u.email}</td>
                <td style={{ padding: "10px 10px", color: "#999" }}>
                  {new Date(u.created_at).toLocaleDateString()}
                </td>
                <td style={{ padding: "10px 10px" }}>
                  <button
                    onClick={() => deleteUser(u.id)}
                    style={{ background: "none", border: "1px solid #fcc", color: "#c00", borderRadius: 4, padding: "3px 10px", cursor: "pointer", fontSize: 12 }}
                  >
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
