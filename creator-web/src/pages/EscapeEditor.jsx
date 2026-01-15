import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import apiClient from '../api/client';
import StepEditor from '../components/StepEditor';
import ImageUploader from '../components/ImageUploader';
import LocationPicker from '../components/LocationPicker';

function EscapeEditor() {
  const { id } = useParams();
  const navigate = useNavigate();

  const [escape, setEscape] = useState(null);
  const [steps, setSteps] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [activeTab, setActiveTab] = useState('info'); // 'info' or 'steps'

  useEffect(() => {
    loadEscape();
    loadSteps();
  }, [id]);

  const loadEscape = async () => {
    try {
      const data = await apiClient.getEscape(id);
      setEscape(data);
    } catch (err) {
      setError('Erreur lors du chargement de l\'escape');
      if (err.message.includes('401')) {
        navigate('/login');
      }
    } finally {
      setLoading(false);
    }
  };

  const loadSteps = async () => {
    try {
      const data = await apiClient.getSteps(id);
      setSteps(data.sort((a, b) => a.order - b.order));
    } catch (err) {
      console.error('Error loading steps:', err);
    }
  };

  const handleSaveInfo = async (e) => {
    e.preventDefault();
    setSaving(true);
    setError('');
    setSuccess('');

    try {
      const updated = await apiClient.updateEscape(id, escape);
      setEscape(updated);
      setSuccess('Informations sauvegardées !');
      setTimeout(() => setSuccess(''), 3000);
    } catch (err) {
      setError(err.message || 'Erreur lors de la sauvegarde');
    } finally {
      setSaving(false);
    }
  };

  const handleSubmit = async () => {
    if (steps.length < 2) {
      setError('Vous devez avoir au moins 2 étapes pour soumettre votre escape.');
      return;
    }

    if (!window.confirm('Êtes-vous sûr de vouloir soumettre cet escape pour révision ?')) {
      return;
    }

    try {
      await apiClient.submitEscape(id);
      setSuccess('Escape soumis pour révision !');
      await loadEscape();
    } catch (err) {
      setError(err.message || 'Erreur lors de la soumission');
    }
  };

  const handleDeleteEscape = async () => {
    if (!window.confirm('Êtes-vous sûr de vouloir supprimer cet escape ? Cette action est irréversible.')) {
      return;
    }

    try {
      await apiClient.deleteEscape(id);
      navigate('/dashboard');
    } catch (err) {
      setError(err.message || 'Erreur lors de la suppression');
    }
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

  if (!escape) {
    return (
      <div className="container">
        <div className="alert alert-error">Escape introuvable</div>
      </div>
    );
  }

  const canEdit = escape.status === 'draft' || escape.status === 'rejected' || escape.status === 'published';

  return (
    <div className="container">
      {/* Header */}
      <div className="card">
        <div className="flex items-center justify-between">
          <div style={{ flex: 1 }}>
            <div className="flex items-center gap-2" style={{ marginBottom: '8px' }}>
              <h1 style={{ marginBottom: 0 }}>{escape.title}</h1>
              <span className={`badge badge-${escape.status}`}>
                {escape.status === 'draft' ? 'Brouillon' :
                 escape.status === 'submitted' ? 'En révision' :
                 escape.status === 'published' ? 'Publié' :
                 escape.status === 'rejected' ? 'Rejeté' : escape.status}
              </span>
            </div>
            <button
              className="btn btn-secondary btn-small"
              onClick={() => navigate('/dashboard')}
            >
              ← Retour au dashboard
            </button>
          </div>
        </div>
      </div>

      {error && <div className="alert alert-error">{error}</div>}
      {success && <div className="alert alert-success">{success}</div>}

      {escape.reject_reason && (
        <div className="alert alert-warning">
          <strong>Raison du rejet :</strong> {escape.reject_reason}
        </div>
      )}

      {/* Tabs */}
      <div className="card" style={{ padding: '0', overflow: 'hidden' }}>
        <div style={{ display: 'flex', borderBottom: '1px solid var(--border)' }}>
          <button
            style={{
              flex: 1,
              padding: '16px',
              border: 'none',
              background: activeTab === 'info' ? 'white' : 'var(--bg-light)',
              borderBottom: activeTab === 'info' ? '3px solid var(--primary)' : 'none',
              cursor: 'pointer',
              fontWeight: activeTab === 'info' ? '600' : 'normal',
            }}
            onClick={() => setActiveTab('info')}
          >
            📝 Informations générales
          </button>
          <button
            style={{
              flex: 1,
              padding: '16px',
              border: 'none',
              background: activeTab === 'steps' ? 'white' : 'var(--bg-light)',
              borderBottom: activeTab === 'steps' ? '3px solid var(--primary)' : 'none',
              cursor: 'pointer',
              fontWeight: activeTab === 'steps' ? '600' : 'normal',
            }}
            onClick={() => setActiveTab('steps')}
          >
            🗺️ Étapes ({steps.length})
          </button>
        </div>

        <div style={{ padding: '24px' }}>
          {activeTab === 'info' && (
            <InfoTab
              escape={escape}
              setEscape={setEscape}
              canEdit={canEdit}
              saving={saving}
              onSave={handleSaveInfo}
            />
          )}

          {activeTab === 'steps' && (
            <StepsTab
              escapeId={id}
              steps={steps}
              canEdit={canEdit}
              onStepsChanged={loadSteps}
            />
          )}
        </div>
      </div>

      {/* Actions */}
      {canEdit && (
        <div className="card">
          <div className="flex gap-2 justify-between">
            <button
              className="btn btn-danger"
              onClick={handleDeleteEscape}
            >
              🗑️ Supprimer cet escape
            </button>
            <button
              className="btn btn-success"
              onClick={handleSubmit}
              disabled={steps.length < 2}
            >
              ✅ Soumettre pour révision
            </button>
          </div>
          {steps.length < 2 && (
            <p style={{ marginTop: '12px', color: 'var(--text-muted)', fontSize: '14px', marginBottom: 0 }}>
              Vous devez avoir au moins 2 étapes pour soumettre votre escape.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

// Info Tab Component
function InfoTab({ escape, setEscape, canEdit, saving, onSave }) {
  return (
    <form onSubmit={onSave}>
      <div className="form-group">
        <label className="form-label">Titre *</label>
        <input
          type="text"
          className="form-input"
          value={escape.title}
          onChange={(e) => setEscape({ ...escape, title: e.target.value })}
          required
          disabled={!canEdit || saving}
        />
      </div>

      <div className="form-group">
        <label className="form-label">Description</label>
        <textarea
          className="form-textarea"
          value={escape.description}
          onChange={(e) => setEscape({ ...escape, description: e.target.value })}
          placeholder="Décrivez votre escape..."
          disabled={!canEdit || saving}
          rows="4"
        />
      </div>

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
        <div className="form-group">
          <label className="form-label">Ville *</label>
          <input
            type="text"
            className="form-input"
            value={escape.city}
            onChange={(e) => setEscape({ ...escape, city: e.target.value })}
            required
            disabled={!canEdit || saving}
          />
        </div>

        <div className="form-group">
          <label className="form-label">Durée (minutes) *</label>
          <input
            type="number"
            className="form-input"
            value={escape.duration_minutes}
            onChange={(e) => setEscape({ ...escape, duration_minutes: parseInt(e.target.value) })}
            required
            min="10"
            max="300"
            disabled={!canEdit || saving}
          />
        </div>
      </div>

      <LocationPicker
        label="Point de départ (coordonnées GPS) *"
        latitude={escape.latitude}
        longitude={escape.longitude}
        onLocationChange={(lat, lng) => setEscape({ ...escape, latitude: lat, longitude: lng })}
        disabled={!canEdit || saving}
      />

      <div className="form-group">
        <label className="form-label">Difficulté</label>
        <select
          className="form-select"
          value={escape.difficulty}
          onChange={(e) => setEscape({ ...escape, difficulty: parseInt(e.target.value) })}
          disabled={!canEdit || saving}
        >
          <option value="1">⭐ Facile</option>
          <option value="2">⭐⭐ Moyen</option>
          <option value="3">⭐⭐⭐ Difficile</option>
        </select>
      </div>

      {/* Section Pénalités */}
      <div style={{ marginTop: '24px', marginBottom: '24px', padding: '16px', background: 'var(--bg-light)', borderRadius: '8px' }}>
        <h3 style={{ marginTop: 0, marginBottom: '16px', fontSize: '18px' }}>⏱️ Pénalités</h3>

        <div className="form-group" style={{ marginBottom: '16px' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={escape.penalize_wrong_answers || false}
              onChange={(e) => setEscape({ ...escape, penalize_wrong_answers: e.target.checked })}
              disabled={!canEdit || saving}
              style={{ width: '18px', height: '18px' }}
            />
            <span>Activer les pénalités pour les mauvaises réponses</span>
          </label>
        </div>

        {escape.penalize_wrong_answers && (
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Minutes de pénalité par mauvaise réponse</label>
            <input
              type="number"
              className="form-input"
              value={escape.wrong_answer_penalty || 0}
              onChange={(e) => setEscape({ ...escape, wrong_answer_penalty: parseInt(e.target.value) || 0 })}
              min="0"
              max="30"
              disabled={!canEdit || saving}
            />
            <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginTop: '8px', marginBottom: 0 }}>
              Chaque mauvaise réponse ajoutera ce nombre de minutes au temps total du joueur.
            </p>
          </div>
        )}
      </div>

      {/* Section Confidentialité */}
      <div style={{ marginTop: '24px', marginBottom: '24px', padding: '16px', background: 'var(--bg-light)', borderRadius: '8px' }}>
        <h3 style={{ marginTop: 0, marginBottom: '16px', fontSize: '18px' }}>🔒 Confidentialité</h3>

        <div className="form-group" style={{ marginBottom: '16px' }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={escape.is_private || false}
              onChange={(e) => setEscape({ ...escape, is_private: e.target.checked, allowed_users: e.target.checked ? (escape.allowed_users || []) : [] })}
              disabled={!canEdit || saving}
              style={{ width: '18px', height: '18px' }}
            />
            <span>Escape privé (accessible uniquement aux utilisateurs autorisés)</span>
          </label>
        </div>

        {escape.is_private && (
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label">Utilisateurs autorisés (noms d'utilisateur séparés par des virgules)</label>
            <textarea
              className="form-textarea"
              value={(escape.allowed_users || []).join(', ')}
              onChange={(e) => {
                const users = e.target.value.split(',').map(u => u.trim()).filter(u => u.length > 0);
                setEscape({ ...escape, allowed_users: users });
              }}
              placeholder="user1, user2, user3"
              disabled={!canEdit || saving}
              rows="2"
            />
            <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginTop: '8px', marginBottom: 0 }}>
              Seuls ces utilisateurs pourront voir et jouer cet escape. Laissez vide pour rendre l'escape public.
            </p>
          </div>
        )}
      </div>

      <div className="form-group">
        <label className="form-label">Message de victoire</label>
        <textarea
          className="form-textarea"
          value={escape.victory_message}
          onChange={(e) => setEscape({ ...escape, victory_message: e.target.value })}
          placeholder="Message affiché lorsque le joueur termine l'escape..."
          disabled={!canEdit || saving}
          rows="3"
        />
      </div>

      {/* Upload d'image */}
      <ImageUploader
        label="Image de l'escape"
        currentImageUrl={escape.image_url}
        onImageUploaded={(url) => setEscape({ ...escape, image_url: url })}
        disabled={!canEdit || saving}
      />

      {canEdit && (
        <button type="submit" className="btn btn-primary" disabled={saving}>
          {saving ? 'Sauvegarde...' : '💾 Sauvegarder'}
        </button>
      )}
    </form>
  );
}

// Steps Tab Component
function StepsTab({ escapeId, steps, canEdit, onStepsChanged }) {
  const [editingStep, setEditingStep] = useState(null);
  const [showCreateModal, setShowCreateModal] = useState(false);

  const handleMoveStep = async (stepId, direction) => {
    const stepIndex = steps.findIndex(s => s.id === stepId);
    if (
      (direction === 'up' && stepIndex === 0) ||
      (direction === 'down' && stepIndex === steps.length - 1)
    ) {
      return;
    }

    const newIndex = direction === 'up' ? stepIndex - 1 : stepIndex + 1;
    const step = steps[stepIndex];
    const otherStep = steps[newIndex];

    try {
      await apiClient.updateStep(escapeId, step.id, { order: otherStep.order });
      await apiClient.updateStep(escapeId, otherStep.id, { order: step.order });
      await onStepsChanged();
    } catch (err) {
      alert('Erreur lors du réordonnancement');
    }
  };

  const handleDeleteStep = async (stepId) => {
    if (!window.confirm('Êtes-vous sûr de vouloir supprimer cette étape ?')) {
      return;
    }

    try {
      await apiClient.deleteStep(escapeId, stepId);
      await onStepsChanged();
    } catch (err) {
      alert('Erreur lors de la suppression');
    }
  };

  return (
    <div>
      {steps.length === 0 ? (
        <div style={{ textAlign: 'center', padding: '40px', color: 'var(--text-muted)' }}>
          <div style={{ fontSize: '48px', marginBottom: '16px' }}>🗺️</div>
          <p>Aucune étape pour le moment.</p>
          <p>Ajoutez votre première étape pour commencer !</p>
        </div>
      ) : (
        <div style={{ display: 'grid', gap: '12px', marginBottom: '20px' }}>
          {steps.map((step, index) => (
            <div key={step.id} className="card" style={{ padding: '16px' }}>
              <div className="flex items-center justify-between">
                <div style={{ flex: 1 }}>
                  <h3 style={{ marginBottom: '4px' }}>
                    #{step.order}. {step.title}
                    {index === steps.length - 1 && (
                      <span style={{ marginLeft: '8px', fontSize: '14px', color: 'var(--success)' }}>
                        🏁 Étape finale
                      </span>
                    )}
                  </h3>
                  <p style={{ fontSize: '14px', color: 'var(--text-muted)', marginBottom: 0 }}>
                    Type: {step.answer_type === 'text' ? 'Texte' :
                           step.answer_type === 'mcq' ? 'QCM' :
                           step.answer_type === 'numeric' ? 'Numérique' :
                           step.answer_type === 'matching' ? 'Association' :
                           'Narration'}
                    {step.latitude && step.longitude && ' | 📍 Géolocalisée'}
                  </p>
                </div>

                {canEdit && (
                  <div className="flex gap-2">
                    <button
                      className="btn btn-secondary btn-small"
                      onClick={() => handleMoveStep(step.id, 'up')}
                      disabled={index === 0}
                      title="Déplacer vers le haut"
                    >
                      ↑
                    </button>
                    <button
                      className="btn btn-secondary btn-small"
                      onClick={() => handleMoveStep(step.id, 'down')}
                      disabled={index === steps.length - 1}
                      title="Déplacer vers le bas"
                    >
                      ↓
                    </button>
                    <button
                      className="btn btn-primary btn-small"
                      onClick={() => setEditingStep(step)}
                    >
                      ✏️ Éditer
                    </button>
                    <button
                      className="btn btn-danger btn-small"
                      onClick={() => handleDeleteStep(step.id)}
                    >
                      🗑️
                    </button>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      )}

      {canEdit && (
        <button
          className="btn btn-primary"
          onClick={() => setShowCreateModal(true)}
        >
          + Ajouter une étape
        </button>
      )}

      {/* Step Editor Modal */}
      {(editingStep || showCreateModal) && (
        <StepEditor
          escapeId={escapeId}
          step={editingStep}
          nextOrder={steps.length + 1}
          onClose={() => {
            setEditingStep(null);
            setShowCreateModal(false);
          }}
          onSaved={async () => {
            setEditingStep(null);
            setShowCreateModal(false);
            await onStepsChanged();
          }}
        />
      )}
    </div>
  );
}

export default EscapeEditor;
