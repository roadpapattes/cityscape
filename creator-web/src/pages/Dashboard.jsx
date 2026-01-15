import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import apiClient from '../api/client';

function Dashboard() {
  const [escapes, setEscapes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [showCreateModal, setShowCreateModal] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    loadEscapes();
  }, []);

  const loadEscapes = async () => {
    try {
      const data = await apiClient.getMyEscapes();
      setEscapes(data);
    } catch (err) {
      setError('Erreur lors du chargement des escapes');
      if (err.message.includes('401')) {
        navigate('/login');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = () => {
    apiClient.logout();
    navigate('/login');
  };

  const handleCreateEscape = () => {
    setShowCreateModal(true);
  };

  const getStatusBadgeClass = (status) => {
    const statusMap = {
      'draft': 'badge-draft',
      'submitted': 'badge-submitted',
      'pending': 'badge-submitted',
      'published': 'badge-published',
      'rejected': 'badge-rejected',
    };
    return statusMap[status] || 'badge-draft';
  };

  const getStatusLabel = (status) => {
    const labelMap = {
      'draft': 'Brouillon',
      'submitted': 'En révision',
      'pending': 'En attente',
      'published': 'Publié',
      'rejected': 'Rejeté',
    };
    return labelMap[status] || status;
  };

  if (loading) {
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
      {/* Header */}
      <div className="card" style={{ marginBottom: '30px' }}>
        <div className="flex items-center justify-between">
          <div>
            <h1 style={{ marginBottom: '4px' }}>🏙️ CityScape Creator</h1>
            <p style={{ marginBottom: 0 }}>Gérez vos escapes urbains</p>
          </div>
          <div style={{ display: 'flex', gap: '12px' }}>
            <button className="btn btn-secondary btn-small" onClick={() => navigate('/profile')}>
              👤 Mon profil
            </button>
            <button className="btn btn-secondary btn-small" onClick={handleLogout}>
              Déconnexion
            </button>
          </div>
        </div>
      </div>

      {error && (
        <div className="alert alert-error">
          {error}
        </div>
      )}

      {/* Escapes list */}
      <div className="card">
        <div className="flex items-center justify-between mb-3">
          <h2 style={{ marginBottom: 0 }}>Mes Escapes</h2>
          <button className="btn btn-primary" onClick={handleCreateEscape}>
            + Nouvel Escape
          </button>
        </div>

        {escapes.length === 0 ? (
          <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
            <div style={{ fontSize: '48px', marginBottom: '16px' }}>🎯</div>
            <p>Vous n'avez pas encore créé d'escape.</p>
            <p>Cliquez sur "Nouvel Escape" pour commencer !</p>
          </div>
        ) : (
          <div style={{ display: 'grid', gap: '16px' }}>
            {escapes.map((escape) => (
              <div
                key={escape.id}
                className="card"
                style={{ cursor: 'pointer', transition: 'transform 0.2s' }}
                onClick={() => navigate(`/escape/${escape.id}`)}
                onMouseEnter={(e) => e.currentTarget.style.transform = 'translateY(-2px)'}
                onMouseLeave={(e) => e.currentTarget.style.transform = 'translateY(0)'}
              >
                <div className="flex items-center justify-between">
                  <div style={{ flex: 1 }}>
                    <div className="flex items-center gap-2" style={{ marginBottom: '8px' }}>
                      <h3 style={{ marginBottom: 0 }}>{escape.title}</h3>
                      <span className={`badge ${getStatusBadgeClass(escape.status)}`}>
                        {getStatusLabel(escape.status)}
                      </span>
                    </div>
                    <p style={{ marginBottom: '8px' }}>
                      📍 {escape.city} | ⏱️ {escape.duration_minutes} min | ⭐ {escape.difficulty}/3
                    </p>
                    {escape.description && (
                      <p style={{ color: 'var(--text-muted)', fontSize: '14px', marginBottom: 0 }}>
                        {escape.description.substring(0, 100)}
                        {escape.description.length > 100 ? '...' : ''}
                      </p>
                    )}
                    {escape.reject_reason && (
                      <div className="alert alert-warning" style={{ marginTop: '12px' }}>
                        <strong>Raison du rejet :</strong> {escape.reject_reason}
                      </div>
                    )}
                  </div>
                  <div style={{ fontSize: '32px', marginLeft: '20px' }}>
                    {escape.status === 'published' ? '✅' :
                     escape.status === 'rejected' ? '❌' :
                     escape.status === 'submitted' ? '⏳' : '📝'}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Create Modal */}
      {showCreateModal && (
        <CreateEscapeModal
          onClose={() => setShowCreateModal(false)}
          onCreated={(newEscape) => {
            setShowCreateModal(false);
            navigate(`/escape/${newEscape.id}`);
          }}
        />
      )}
    </div>
  );
}

// Simple modal for creating a new escape
function CreateEscapeModal({ onClose, onCreated }) {
  const [title, setTitle] = useState('');
  const [city, setCity] = useState('');
  const [duration, setDuration] = useState(60);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      const newEscape = await apiClient.createEscape({
        title,
        city,
        duration_minutes: duration,
        latitude: 48.8566,  // Default Paris coordinates
        longitude: 2.3522,
        description: '',
        difficulty: 1,
      });
      onCreated(newEscape);
    } catch (err) {
      setError(err.message || 'Erreur lors de la création');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div
      style={{
        position: 'fixed',
        top: 0,
        left: 0,
        right: 0,
        bottom: 0,
        background: 'rgba(0, 0, 0, 0.5)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 1000,
      }}
      onClick={onClose}
    >
      <div
        className="card"
        style={{ maxWidth: '500px', width: '100%', margin: '20px' }}
        onClick={(e) => e.stopPropagation()}
      >
        <h2>Créer un nouvel escape</h2>

        {error && <div className="alert alert-error">{error}</div>}

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label className="form-label">Titre *</label>
            <input
              type="text"
              className="form-input"
              value={title}
              onChange={(e) => setTitle(e.target.value)}
              required
              placeholder="Ex: Mystère à Montmartre"
              disabled={loading}
            />
          </div>

          <div className="form-group">
            <label className="form-label">Ville *</label>
            <input
              type="text"
              className="form-input"
              value={city}
              onChange={(e) => setCity(e.target.value)}
              required
              placeholder="Ex: Paris"
              disabled={loading}
            />
          </div>

          <div className="form-group">
            <label className="form-label">Durée estimée (minutes) *</label>
            <input
              type="number"
              className="form-input"
              value={duration}
              onChange={(e) => setDuration(parseInt(e.target.value))}
              required
              min="10"
              max="300"
              disabled={loading}
            />
          </div>

          <div className="flex gap-2">
            <button
              type="button"
              className="btn btn-secondary"
              style={{ flex: 1 }}
              onClick={onClose}
              disabled={loading}
            >
              Annuler
            </button>
            <button
              type="submit"
              className="btn btn-primary"
              style={{ flex: 1 }}
              disabled={loading}
            >
              {loading ? 'Création...' : 'Créer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default Dashboard;
