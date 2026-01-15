import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import apiClient from '../api/client';

function Profile() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [activeTab, setActiveTab] = useState('info'); // 'info' or 'password'
  const navigate = useNavigate();

  // Profile form state
  const [profileForm, setProfileForm] = useState({
    username: '',
    email: '',
    first_name: '',
    last_name: '',
  });
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileError, setProfileError] = useState('');
  const [profileSuccess, setProfileSuccess] = useState('');

  // Password form state
  const [passwordForm, setPasswordForm] = useState({
    oldPassword: '',
    newPassword: '',
    confirmPassword: '',
  });
  const [passwordSaving, setPasswordSaving] = useState(false);
  const [passwordError, setPasswordError] = useState('');
  const [passwordSuccess, setPasswordSuccess] = useState('');

  useEffect(() => {
    loadProfile();
  }, []);

  const loadProfile = async () => {
    try {
      const data = await apiClient.getUserProfile();
      setUser(data);
      setProfileForm({
        username: data.username || '',
        email: data.email || '',
        first_name: data.first_name || '',
        last_name: data.last_name || '',
      });
    } catch (err) {
      if (err.message.includes('401')) {
        navigate('/login');
      }
    } finally {
      setLoading(false);
    }
  };

  const handleProfileSubmit = async (e) => {
    e.preventDefault();
    setProfileSaving(true);
    setProfileError('');
    setProfileSuccess('');

    try {
      await apiClient.updateUserProfile(profileForm);
      setProfileSuccess('✓ Profil mis à jour avec succès');
      setTimeout(() => setProfileSuccess(''), 3000);
    } catch (err) {
      setProfileError(err.message || 'Erreur lors de la mise à jour du profil');
    } finally {
      setProfileSaving(false);
    }
  };

  const handlePasswordSubmit = async (e) => {
    e.preventDefault();
    setPasswordSaving(true);
    setPasswordError('');
    setPasswordSuccess('');

    // Validation
    if (passwordForm.newPassword !== passwordForm.confirmPassword) {
      setPasswordError('Les mots de passe ne correspondent pas');
      setPasswordSaving(false);
      return;
    }

    if (passwordForm.newPassword.length < 8) {
      setPasswordError('Le mot de passe doit contenir au moins 8 caractères');
      setPasswordSaving(false);
      return;
    }

    try {
      await apiClient.changePassword(passwordForm.oldPassword, passwordForm.newPassword);
      setPasswordSuccess('✓ Mot de passe changé avec succès');
      setPasswordForm({ oldPassword: '', newPassword: '', confirmPassword: '' });
      setTimeout(() => setPasswordSuccess(''), 3000);
    } catch (err) {
      setPasswordError(err.message || 'Erreur lors du changement de mot de passe');
    } finally {
      setPasswordSaving(false);
    }
  };

  const handleBack = () => {
    navigate('/dashboard');
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
            <h1 style={{ marginBottom: '4px' }}>👤 Mon Profil</h1>
            <p style={{ marginBottom: 0 }}>Gérez vos informations personnelles</p>
          </div>
          <button className="btn btn-secondary btn-small" onClick={handleBack}>
            ← Retour au dashboard
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="card" style={{ marginBottom: '20px' }}>
        <div style={{ display: 'flex', gap: '10px', borderBottom: '2px solid var(--border-color)', marginBottom: 0 }}>
          <button
            className={`tab-button ${activeTab === 'info' ? 'active' : ''}`}
            onClick={() => setActiveTab('info')}
            style={{
              padding: '12px 24px',
              border: 'none',
              background: 'none',
              cursor: 'pointer',
              fontSize: '16px',
              fontWeight: activeTab === 'info' ? '600' : '400',
              color: activeTab === 'info' ? 'var(--primary)' : 'var(--text-muted)',
              borderBottom: activeTab === 'info' ? '3px solid var(--primary)' : '3px solid transparent',
              marginBottom: '-2px',
              transition: 'all 0.2s',
            }}
          >
            📋 Informations personnelles
          </button>
          <button
            className={`tab-button ${activeTab === 'password' ? 'active' : ''}`}
            onClick={() => setActiveTab('password')}
            style={{
              padding: '12px 24px',
              border: 'none',
              background: 'none',
              cursor: 'pointer',
              fontSize: '16px',
              fontWeight: activeTab === 'password' ? '600' : '400',
              color: activeTab === 'password' ? 'var(--primary)' : 'var(--text-muted)',
              borderBottom: activeTab === 'password' ? '3px solid var(--primary)' : '3px solid transparent',
              marginBottom: '-2px',
              transition: 'all 0.2s',
            }}
          >
            🔒 Changer le mot de passe
          </button>
        </div>
      </div>

      {/* Profile Info Tab */}
      {activeTab === 'info' && (
        <div className="card">
          <h2 style={{ marginBottom: '20px' }}>Informations personnelles</h2>

          {profileError && (
            <div className="alert alert-error" style={{ marginBottom: '20px' }}>
              {profileError}
            </div>
          )}

          {profileSuccess && (
            <div className="alert alert-success" style={{ marginBottom: '20px' }}>
              {profileSuccess}
            </div>
          )}

          <form onSubmit={handleProfileSubmit}>
            <div className="form-group">
              <label className="form-label">Nom d'utilisateur</label>
              <input
                type="text"
                className="form-input"
                value={profileForm.username}
                onChange={(e) => setProfileForm({ ...profileForm, username: e.target.value })}
                disabled={profileSaving}
                required
              />
            </div>

            <div className="form-group">
              <label className="form-label">Email</label>
              <input
                type="email"
                className="form-input"
                value={profileForm.email}
                onChange={(e) => setProfileForm({ ...profileForm, email: e.target.value })}
                disabled={profileSaving}
                required
              />
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '20px' }}>
              <div className="form-group">
                <label className="form-label">Prénom</label>
                <input
                  type="text"
                  className="form-input"
                  value={profileForm.first_name}
                  onChange={(e) => setProfileForm({ ...profileForm, first_name: e.target.value })}
                  disabled={profileSaving}
                  placeholder="Optionnel"
                />
              </div>

              <div className="form-group">
                <label className="form-label">Nom</label>
                <input
                  type="text"
                  className="form-input"
                  value={profileForm.last_name}
                  onChange={(e) => setProfileForm({ ...profileForm, last_name: e.target.value })}
                  disabled={profileSaving}
                  placeholder="Optionnel"
                />
              </div>
            </div>

            <button
              type="submit"
              className="btn btn-primary"
              disabled={profileSaving}
            >
              {profileSaving ? '⏳ Enregistrement...' : '💾 Enregistrer les modifications'}
            </button>
          </form>
        </div>
      )}

      {/* Password Tab */}
      {activeTab === 'password' && (
        <div className="card">
          <h2 style={{ marginBottom: '20px' }}>Changer le mot de passe</h2>

          {passwordError && (
            <div className="alert alert-error" style={{ marginBottom: '20px' }}>
              {passwordError}
            </div>
          )}

          {passwordSuccess && (
            <div className="alert alert-success" style={{ marginBottom: '20px' }}>
              {passwordSuccess}
            </div>
          )}

          <form onSubmit={handlePasswordSubmit}>
            <div className="form-group">
              <label className="form-label">Mot de passe actuel</label>
              <input
                type="password"
                className="form-input"
                value={passwordForm.oldPassword}
                onChange={(e) => setPasswordForm({ ...passwordForm, oldPassword: e.target.value })}
                disabled={passwordSaving}
                required
              />
            </div>

            <div className="form-group">
              <label className="form-label">Nouveau mot de passe</label>
              <input
                type="password"
                className="form-input"
                value={passwordForm.newPassword}
                onChange={(e) => setPasswordForm({ ...passwordForm, newPassword: e.target.value })}
                disabled={passwordSaving}
                required
                minLength={8}
                placeholder="Au moins 8 caractères"
              />
            </div>

            <div className="form-group">
              <label className="form-label">Confirmer le nouveau mot de passe</label>
              <input
                type="password"
                className="form-input"
                value={passwordForm.confirmPassword}
                onChange={(e) => setPasswordForm({ ...passwordForm, confirmPassword: e.target.value })}
                disabled={passwordSaving}
                required
                minLength={8}
                placeholder="Répétez le nouveau mot de passe"
              />
            </div>

            <button
              type="submit"
              className="btn btn-primary"
              disabled={passwordSaving}
            >
              {passwordSaving ? '⏳ Changement...' : '🔒 Changer le mot de passe'}
            </button>
          </form>
        </div>
      )}
    </div>
  );
}

export default Profile;
