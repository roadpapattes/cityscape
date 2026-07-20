import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import apiClient from '../api/client';

const ROLE_LABELS = {
  superadmin: 'Superadmin',
  staff: 'Staff',
  createur: 'Créateur',
  joueur: 'Joueur',
};

const STATUS_LABELS = {
  draft: 'Brouillon',
  submitted: 'En révision',
  published: 'Publié',
  rejected: 'Rejeté',
};

function Admin() {
  const navigate = useNavigate();
  const [checking, setChecking] = useState(true);
  const [isSuperuser, setIsSuperuser] = useState(false);
  const [activeTab, setActiveTab] = useState('stats'); // 'stats' | 'users' | 'escapes' | 'sessions'

  // Filtres pilotables depuis le dashboard (clic sur un chiffre)
  const [usersActiveOnly, setUsersActiveOnly] = useState(false);
  const [escapesStatusFilter, setEscapesStatusFilter] = useState('submitted');
  const [sessionsStatusFilter, setSessionsStatusFilter] = useState('in_progress');

  const goToUsers = (activeOnly) => {
    setUsersActiveOnly(activeOnly);
    setActiveTab('users');
  };
  const goToEscapes = (statusValue) => {
    setEscapesStatusFilter(statusValue);
    setActiveTab('escapes');
  };
  const goToSessions = (statusValue) => {
    setSessionsStatusFilter(statusValue);
    setActiveTab('sessions');
  };

  useEffect(() => {
    checkAccess();
  }, []);

  const checkAccess = async () => {
    try {
      const profile = await apiClient.getUserProfile();
      if (!profile.is_staff) {
        navigate('/dashboard');
        return;
      }
      setIsSuperuser(!!profile.is_superuser);
    } catch (err) {
      if (err.message.includes('401')) {
        navigate('/login');
        return;
      }
    } finally {
      setChecking(false);
    }
  };

  if (checking) {
    return (
      <div className="container">
        <div className="loading-container">
          <div className="spinner"></div>
        </div>
      </div>
    );
  }

  return (
    <div className="container">
      <div className="card">
        <div className="flex items-center justify-between">
          <div>
            <h1 style={{ marginBottom: '4px' }}>🛠️ Administration</h1>
            <p style={{ marginBottom: 0 }}>Utilisateurs, modération des escapes et statistiques</p>
          </div>
          <button className="btn btn-secondary btn-small" onClick={() => navigate('/dashboard')}>
            ← Retour au dashboard
          </button>
        </div>
      </div>

      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ display: 'flex', borderBottom: '1px solid var(--border)' }}>
          {[
            { key: 'stats', label: '📊 Tableau de bord' },
            { key: 'users', label: '👥 Utilisateurs' },
            { key: 'escapes', label: '🎯 Modération escapes' },
            { key: 'sessions', label: '🕹️ Sessions' },
          ].map((tab) => (
            <button
              key={tab.key}
              style={{
                flex: 1,
                padding: '16px',
                border: 'none',
                background: activeTab === tab.key ? 'white' : 'var(--bg-light)',
                borderBottom: activeTab === tab.key ? '3px solid var(--primary)' : 'none',
                cursor: 'pointer',
                fontWeight: activeTab === tab.key ? '600' : 'normal',
              }}
              onClick={() => setActiveTab(tab.key)}
            >
              {tab.label}
            </button>
          ))}
        </div>

        <div style={{ padding: '24px' }}>
          {activeTab === 'stats' && (
            <StatsTab onGoToUsers={goToUsers} onGoToEscapes={goToEscapes} onGoToSessions={goToSessions} />
          )}
          {activeTab === 'users' && (
            <UsersTab isSuperuser={isSuperuser} activeOnly={usersActiveOnly} onActiveOnlyChange={setUsersActiveOnly} />
          )}
          {activeTab === 'escapes' && (
            <EscapesTab statusFilter={escapesStatusFilter} onStatusFilterChange={setEscapesStatusFilter} />
          )}
          {activeTab === 'sessions' && (
            <SessionsTab statusFilter={sessionsStatusFilter} onStatusFilterChange={setSessionsStatusFilter} />
          )}
        </div>
      </div>
    </div>
  );
}

// ---------------- Tableau de bord ----------------
function StatsTab({ onGoToUsers, onGoToEscapes, onGoToSessions }) {
  const [stats, setStats] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    apiClient.getAdminStats()
      .then(setStats)
      .catch((err) => setError(err.message || 'Erreur lors du chargement des statistiques'))
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="loading-container"><div className="spinner"></div></div>;
  if (error) return <div className="alert alert-error">{error}</div>;
  if (!stats) return null;

  const statCard = (label, value, onClick) => (
    <div
      className="card"
      style={{ textAlign: 'center', marginBottom: 0, cursor: onClick ? 'pointer' : 'default' }}
      onClick={onClick}
    >
      <div style={{ fontSize: '32px', fontWeight: 700, color: 'var(--primary)' }}>{value}</div>
      <div style={{ color: 'var(--text-muted)' }}>{label}</div>
    </div>
  );

  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: '16px', marginBottom: '24px' }}>
        {statCard('Utilisateurs actifs', `${stats.users_active} / ${stats.users_total}`, () => onGoToUsers(true))}
        {statCard('Sessions en cours', stats.sessions_in_progress, () => onGoToSessions('in_progress'))}
        {statCard('Sessions terminées', stats.sessions_completed, () => onGoToSessions('completed'))}
      </div>

      <h3>Escapes par statut</h3>
      <p style={{ marginTop: '-8px', marginBottom: '16px', fontSize: '14px' }}>Cliquez sur un chiffre pour voir la liste correspondante.</p>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: '16px' }}>
        {Object.entries(stats.escapes_by_status).map(([st, count]) => (
          <div
            key={st}
            className="card"
            style={{ textAlign: 'center', marginBottom: 0, cursor: 'pointer' }}
            onClick={() => onGoToEscapes(st)}
          >
            <div style={{ fontSize: '24px', fontWeight: 700 }}>{count}</div>
            <span className={`badge badge-${st}`}>{STATUS_LABELS[st] || st}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------------- Utilisateurs ----------------
function UsersTab({ isSuperuser, activeOnly, onActiveOnlyChange }) {
  const [users, setUsers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState(null);

  useEffect(() => {
    loadUsers();
  }, []);

  const loadUsers = async () => {
    try {
      const data = await apiClient.getAdminUsers();
      setUsers(data);
    } catch (err) {
      setError(err.message || 'Erreur lors du chargement des utilisateurs');
    } finally {
      setLoading(false);
    }
  };

  const toggleActive = async (user) => {
    const activating = !user.is_active;
    if (!activating && !window.confirm(`Désactiver le compte "${user.username}" ?`)) return;

    setBusyId(user.id);
    setError('');
    try {
      await apiClient.updateAdminUser(user.id, { is_active: activating });
      await loadUsers();
    } catch (err) {
      setError(err.message || 'Erreur lors de la mise à jour');
    } finally {
      setBusyId(null);
    }
  };

  const toggleStaff = async (user) => {
    const promoting = !user.is_staff;
    const verb = promoting ? 'Promouvoir' : 'Retirer le statut staff de';
    if (!window.confirm(`${verb} "${user.username}" ?`)) return;

    setBusyId(user.id);
    setError('');
    try {
      await apiClient.updateAdminUser(user.id, { is_staff: promoting });
      await loadUsers();
    } catch (err) {
      setError(err.message || 'Erreur lors de la mise à jour');
    } finally {
      setBusyId(null);
    }
  };

  if (loading) return <div className="loading-container"><div className="spinner"></div></div>;

  const visibleUsers = activeOnly ? users.filter((u) => u.is_active) : users;

  return (
    <div>
      <div className="form-group" style={{ maxWidth: '300px' }}>
        <label className="form-label" style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
          <input
            type="checkbox"
            checked={activeOnly}
            onChange={(e) => onActiveOnlyChange(e.target.checked)}
          />
          Afficher uniquement les comptes actifs
        </label>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      <div style={{ display: 'grid', gap: '12px' }}>
        {visibleUsers.map((user) => (
          <div key={user.id} className="card" style={{ marginBottom: 0 }}>
            <div className="flex items-center justify-between" style={{ flexWrap: 'wrap', gap: '12px' }}>
              <div>
                <div className="flex items-center gap-2" style={{ marginBottom: '4px' }}>
                  <strong>{user.username}</strong>
                  <span className={`badge badge-role-${user.role}`}>{ROLE_LABELS[user.role] || user.role}</span>
                  <span className={`badge ${user.is_active ? 'badge-active' : 'badge-inactive'}`}>
                    {user.is_active ? 'Actif' : 'Désactivé'}
                  </span>
                  {!user.email_verified && <span className="badge badge-submitted">Email non vérifié</span>}
                </div>
                <p style={{ marginBottom: 0, fontSize: '14px' }}>
                  {user.email || '-'} · {user.escapes_created} escape(s) créé(s) · {user.sessions_count} session(s)
                </p>
              </div>

              <div className="flex gap-2">
                {isSuperuser && user.role !== 'superadmin' && (
                  <button
                    className="btn btn-secondary btn-small"
                    disabled={busyId === user.id}
                    onClick={() => toggleStaff(user)}
                  >
                    {user.is_staff ? 'Retirer staff' : 'Promouvoir staff'}
                  </button>
                )}
                <button
                  className={`btn btn-small ${user.is_active ? 'btn-danger' : 'btn-success'}`}
                  disabled={busyId === user.id}
                  onClick={() => toggleActive(user)}
                >
                  {user.is_active ? 'Désactiver' : 'Activer'}
                </button>
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ---------------- Modération escapes ----------------
function EscapesTab({ statusFilter, onStatusFilterChange }) {
  const navigate = useNavigate();
  const [escapes, setEscapes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [busyId, setBusyId] = useState(null);
  const [rejectingId, setRejectingId] = useState(null);

  useEffect(() => {
    loadEscapes();
  }, [statusFilter]);

  const loadEscapes = async () => {
    setLoading(true);
    try {
      const data = await apiClient.getEscapesByStatus(statusFilter);
      setEscapes(data);
    } catch (err) {
      setError(err.message || 'Erreur lors du chargement des escapes');
    } finally {
      setLoading(false);
    }
  };

  const handleApprove = async (escape) => {
    if (!window.confirm(`Approuver et publier "${escape.title}" ?`)) return;
    setBusyId(escape.id);
    setError('');
    try {
      await apiClient.publishEscape(escape.id);
      await loadEscapes();
    } catch (err) {
      setError(err.message || 'Erreur lors de la publication');
    } finally {
      setBusyId(null);
    }
  };

  const handleReject = async (escape, reason) => {
    setBusyId(escape.id);
    setError('');
    try {
      await apiClient.rejectEscape(escape.id, reason);
      setRejectingId(null);
      await loadEscapes();
    } catch (err) {
      setError(err.message || 'Erreur lors du rejet');
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div>
      <div className="form-group" style={{ maxWidth: '240px' }}>
        <label className="form-label">Filtrer par statut</label>
        <select
          className="form-select"
          value={statusFilter}
          onChange={(e) => onStatusFilterChange(e.target.value)}
        >
          <option value="submitted">En révision</option>
          <option value="published">Publiés</option>
          <option value="rejected">Rejetés</option>
          <option value="draft">Brouillons</option>
          <option value="all">Tous</option>
        </select>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      {loading ? (
        <div className="loading-container"><div className="spinner"></div></div>
      ) : escapes.length === 0 ? (
        <p style={{ color: 'var(--text-muted)' }}>Aucun escape dans ce statut.</p>
      ) : (
        <div style={{ display: 'grid', gap: '12px' }}>
          {escapes.map((escape) => {
            const canApprove = escape.status === 'submitted';
            const canReject = escape.status === 'submitted' || escape.status === 'published';

            return (
              <div key={escape.id} className="card" style={{ marginBottom: 0 }}>
                <div className="flex items-center justify-between" style={{ flexWrap: 'wrap', gap: '12px' }}>
                  <div>
                    <div className="flex items-center gap-2" style={{ marginBottom: '4px' }}>
                      <strong>{escape.title}</strong>
                      <span className={`badge badge-${escape.status}`}>{STATUS_LABELS[escape.status] || escape.status}</span>
                    </div>
                    <p style={{ marginBottom: 0, fontSize: '14px' }}>
                      Par {escape.creator_username || '?'} · 📍 {escape.city} · ⏱️ {escape.duration_minutes} min
                    </p>
                    {escape.reject_reason && (
                      <p style={{ marginBottom: 0, fontSize: '14px', color: 'var(--danger)' }}>
                        Motif du dernier rejet : {escape.reject_reason}
                      </p>
                    )}
                  </div>

                  <div className="flex gap-2">
                    <button className="btn btn-secondary btn-small" onClick={() => navigate(`/escape/${escape.id}`)}>
                      Voir
                    </button>
                    {canApprove && (
                      <button
                        className="btn btn-success btn-small"
                        disabled={busyId === escape.id}
                        onClick={() => handleApprove(escape)}
                      >
                        Approuver
                      </button>
                    )}
                    {canReject && (
                      <button
                        className="btn btn-danger btn-small"
                        disabled={busyId === escape.id}
                        onClick={() => setRejectingId(escape.id)}
                      >
                        Rejeter
                      </button>
                    )}
                  </div>
                </div>

                {rejectingId === escape.id && (
                  <RejectForm
                    busy={busyId === escape.id}
                    onCancel={() => setRejectingId(null)}
                    onConfirm={(reason) => handleReject(escape, reason)}
                  />
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ---------------- Sessions ----------------
function SessionsTab({ statusFilter, onStatusFilterChange }) {
  const [sessions, setSessions] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    loadSessions();
  }, [statusFilter]);

  const loadSessions = async () => {
    setLoading(true);
    try {
      const data = await apiClient.getAdminSessions(statusFilter);
      setSessions(data);
    } catch (err) {
      setError(err.message || 'Erreur lors du chargement des sessions');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div>
      <div className="form-group" style={{ maxWidth: '240px' }}>
        <label className="form-label">Filtrer</label>
        <select
          className="form-select"
          value={statusFilter}
          onChange={(e) => onStatusFilterChange(e.target.value)}
        >
          <option value="in_progress">En cours</option>
          <option value="completed">Terminées</option>
        </select>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      {loading ? (
        <div className="loading-container"><div className="spinner"></div></div>
      ) : sessions.length === 0 ? (
        <p style={{ color: 'var(--text-muted)' }}>Aucune session dans ce statut.</p>
      ) : (
        <div style={{ display: 'grid', gap: '12px' }}>
          {sessions.map((sess) => (
            <div key={sess.id} className="card" style={{ marginBottom: 0 }}>
              <div className="flex items-center gap-2" style={{ marginBottom: '4px' }}>
                <strong>{sess.username}</strong>
                <span style={{ color: 'var(--text-muted)' }}>→</span>
                <span>{sess.escape_title}</span>
              </div>
              <p style={{ marginBottom: 0, fontSize: '14px' }}>
                Étape {sess.current_step_index}/{sess.total_steps} ({sess.progress_percent}%)
                {' · '}{Math.floor((sess.play_time_seconds || 0) / 60)} min de jeu
                {' · '}débuté le {new Date(sess.started_at).toLocaleString('fr-FR')}
                {sess.completed_at && <> · terminé le {new Date(sess.completed_at).toLocaleString('fr-FR')}</>}
              </p>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function RejectForm({ busy, onCancel, onConfirm }) {
  const [reason, setReason] = useState('');

  return (
    <div style={{ marginTop: '16px', paddingTop: '16px', borderTop: '1px solid var(--border)' }}>
      <div className="form-group" style={{ marginBottom: '12px' }}>
        <label className="form-label">Motif du rejet</label>
        <textarea
          className="form-textarea"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          placeholder="Expliquez brièvement le refus"
          disabled={busy}
        />
      </div>
      <div className="flex gap-2">
        <button className="btn btn-secondary btn-small" onClick={onCancel} disabled={busy}>
          Annuler
        </button>
        <button
          className="btn btn-danger btn-small"
          disabled={busy || !reason.trim()}
          onClick={() => onConfirm(reason.trim())}
        >
          Confirmer le rejet
        </button>
      </div>
    </div>
  );
}

export default Admin;
