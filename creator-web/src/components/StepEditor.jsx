import { useState, useEffect } from 'react';
import apiClient from '../api/client';
import ImageUploader from './ImageUploader';
import LocationPicker from './LocationPicker';

function StepEditor({ escapeId, step, nextOrder, onClose, onSaved }) {
  const isEditing = !!step;

  const [formData, setFormData] = useState({
    order: step?.order || nextOrder,
    title: step?.title || '',
    text: step?.text || '',
    answer_type: step?.answer_type || 'text',
    latitude: step?.latitude || '',
    longitude: step?.longitude || '',
    show_location: step?.show_location !== false, // true par défaut
    image_url: step?.image_url || '',
    image_credit: step?.image_credit || '',

    // Text answer
    answer_text: step?.answer_text || '',

    // MCQ
    options: step?.options || ['', '', '', ''],
    correct_index: step?.correct_index ?? 0,

    // Matching
    match_left: step?.match_left || ['', ''],
    match_right: step?.match_right || ['', ''],
    match_pairs: step?.match_pairs || [[0, 0], [1, 1]],

    // Hints
    hints: step?.hints || [],
    hint_penalty: step?.hint_penalty || 0,

    // Location ("Point à atteindre")
    radius_m: step?.radius_m ?? 30,
    reveal_mode: step?.reveal_mode || 'guided',
    auto_validate: step?.auto_validate !== false, // true par défaut
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');

    try {
      // Validate based on answer type
      if ((formData.answer_type === 'text' || formData.answer_type === 'cesar') && !formData.answer_text) {
        throw new Error('La réponse est requise pour une énigme de type texte');
      }

      if (formData.answer_type === 'mcq') {
        if (formData.options.some(opt => !opt.trim())) {
          throw new Error('Toutes les options doivent être remplies pour un QCM');
        }
      }

      if (formData.answer_type === 'numeric' && !formData.answer_text) {
        throw new Error('La réponse numérique est requise');
      }

      if (formData.answer_type === 'matching') {
        if (formData.match_left.some(item => !item.trim()) || formData.match_right.some(item => !item.trim())) {
          throw new Error('Tous les éléments doivent être remplis pour une association');
        }
      }

      if (formData.answer_type === 'location' && (!formData.latitude || !formData.longitude)) {
        throw new Error('Placez le point à atteindre sur la carte pour une énigme de déplacement');
      }

      // Clean data before sending
      const payload = {
        order: formData.order,
        title: formData.title,
        text: formData.text,
        answer_type: formData.answer_type,
        latitude: formData.latitude || null,
        longitude: formData.longitude || null,
        show_location: formData.show_location,
        image_url: formData.image_url || null,
        image_credit: formData.image_credit || '',
        hints: formData.hints,
        hint_penalty: formData.hint_penalty,
      };

      // Add answer-specific fields
      if (formData.answer_type === 'text' || formData.answer_type === 'numeric' || formData.answer_type === 'cesar') {
        payload.answer_text = formData.answer_text;
      }

      if (formData.answer_type === 'mcq') {
        payload.options = formData.options;
        payload.correct_index = formData.correct_index;
      }

      if (formData.answer_type === 'matching') {
        payload.match_left = formData.match_left;
        payload.match_right = formData.match_right;
        payload.match_pairs = formData.match_pairs;
      }

      if (formData.answer_type === 'location') {
        payload.radius_m = parseInt(formData.radius_m, 10) || 30;
        payload.reveal_mode = formData.reveal_mode;
        payload.auto_validate = formData.auto_validate;
      }

      if (isEditing) {
        await apiClient.updateStep(escapeId, step.id, payload);
      } else {
        await apiClient.createStep(escapeId, payload);
      }

      onSaved();
    } catch (err) {
      setError(err.message || 'Erreur lors de la sauvegarde');
    } finally {
      setLoading(false);
    }
  };

  const updateField = (field, value) => {
    setFormData(prev => ({ ...prev, [field]: value }));
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
        padding: '20px',
        overflowY: 'auto',
      }}
      onClick={onClose}
    >
      <div
        className="card"
        style={{ maxWidth: '700px', width: '100%', maxHeight: '90vh', overflowY: 'auto' }}
        onClick={(e) => e.stopPropagation()}
      >
        <h2>{isEditing ? 'Éditer l\'étape' : 'Nouvelle étape'}</h2>

        {error && <div className="alert alert-error">{error}</div>}

        <form onSubmit={handleSubmit}>
          {/* Basic info */}
          <div className="form-group">
            <label className="form-label">Titre de l'étape *</label>
            <input
              type="text"
              className="form-input"
              value={formData.title}
              onChange={(e) => updateField('title', e.target.value)}
              required
              disabled={loading}
              placeholder="Ex: La fontaine mystérieuse"
            />
          </div>

          <div className="form-group">
            <label className="form-label">Description / Consigne *</label>
            <textarea
              className="form-textarea"
              value={formData.text}
              onChange={(e) => updateField('text', e.target.value)}
              required
              disabled={loading}
              rows="4"
              placeholder="Décrivez l'énigme ou donnez des instructions..."
            />
          </div>

          {/* Answer type */}
          <div className="form-group">
            <label className="form-label">Type d'énigme *</label>
            <select
              className="form-select"
              value={formData.answer_type}
              onChange={(e) => updateField('answer_type', e.target.value)}
              disabled={loading}
            >
              <option value="text">Texte libre</option>
              <option value="mcq">QCM (4 choix)</option>
              <option value="numeric">Numérique</option>
              <option value="matching">Association</option>
              <option value="cesar">Code de César</option>
              <option value="narration">Narration (pas d'énigme)</option>
              <option value="location">Point à atteindre (déplacement)</option>
            </select>
          </div>

          {/* Answer fields based on type */}
          {(formData.answer_type === 'text' || formData.answer_type === 'cesar') && (
            <div className="form-group">
              <label className="form-label">Réponse attendue *</label>
              <input
                type="text"
                className="form-input"
                value={formData.answer_text}
                onChange={(e) => updateField('answer_text', e.target.value)}
                required
                disabled={loading}
                placeholder="Ex: Paris"
              />
              <p className="form-help">
                {formData.answer_type === 'cesar'
                  ? 'Écrivez le message chiffré dans le champ "Énoncé / description" ci-dessus, et le message déchiffré ici. Comparaison insensible à la casse et aux espaces.'
                  : 'La comparaison est insensible à la casse et aux espaces'}
              </p>
            </div>
          )}

          {formData.answer_type === 'numeric' && (
            <div className="form-group">
              <label className="form-label">Réponse numérique *</label>
              <input
                type="number"
                step="any"
                className="form-input"
                value={formData.answer_text}
                onChange={(e) => updateField('answer_text', e.target.value)}
                required
                disabled={loading}
                placeholder="Ex: 42"
              />
            </div>
          )}

          {formData.answer_type === 'mcq' && (
            <div>
              <label className="form-label">Options du QCM *</label>
              {formData.options.map((option, index) => (
                <div key={index} className="form-group">
                  <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                    <input
                      type="radio"
                      name="correct"
                      checked={formData.correct_index === index}
                      onChange={() => updateField('correct_index', index)}
                      disabled={loading}
                    />
                    <input
                      type="text"
                      className="form-input"
                      value={option}
                      onChange={(e) => {
                        const newOptions = [...formData.options];
                        newOptions[index] = e.target.value;
                        updateField('options', newOptions);
                      }}
                      required
                      disabled={loading}
                      placeholder={`Option ${index + 1}`}
                      style={{ flex: 1 }}
                    />
                  </div>
                </div>
              ))}
              <p className="form-help">Sélectionnez la bonne réponse en cochant le bouton radio</p>
            </div>
          )}

          {formData.answer_type === 'matching' && (
            <div>
              <label className="form-label">Association *</label>
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px' }}>
                <div>
                  <p style={{ fontWeight: '600', marginBottom: '8px' }}>Colonne gauche</p>
                  {formData.match_left.map((item, index) => (
                    <div key={index} className="form-group">
                      <input
                        type="text"
                        className="form-input"
                        value={item}
                        onChange={(e) => {
                          const newLeft = [...formData.match_left];
                          newLeft[index] = e.target.value;
                          updateField('match_left', newLeft);
                        }}
                        required
                        disabled={loading}
                        placeholder={`Élément ${index + 1}`}
                      />
                    </div>
                  ))}
                  <button
                    type="button"
                    className="btn btn-secondary btn-small"
                    onClick={() => {
                      updateField('match_left', [...formData.match_left, '']);
                      updateField('match_right', [...formData.match_right, '']);
                      updateField('match_pairs', [...formData.match_pairs, [formData.match_left.length, formData.match_right.length]]);
                    }}
                    disabled={loading}
                  >
                    + Ajouter une paire
                  </button>
                </div>

                <div>
                  <p style={{ fontWeight: '600', marginBottom: '8px' }}>Colonne droite</p>
                  {formData.match_right.map((item, index) => (
                    <div key={index} className="form-group">
                      <input
                        type="text"
                        className="form-input"
                        value={item}
                        onChange={(e) => {
                          const newRight = [...formData.match_right];
                          newRight[index] = e.target.value;
                          updateField('match_right', newRight);
                        }}
                        required
                        disabled={loading}
                        placeholder={`Correspond à ${index + 1}`}
                      />
                    </div>
                  ))}
                </div>
              </div>
              <p className="form-help">
                Chaque élément de gauche correspond à l'élément de droite à la même position
              </p>
            </div>
          )}

          {formData.answer_type === 'narration' && (
            <div className="alert alert-info">
              Les étapes de type "Narration" ne nécessitent pas de réponse. Elles servent simplement à raconter l'histoire.
            </div>
          )}

          {formData.answer_type === 'location' && (
            <div className="form-group" style={{ border: '1px solid var(--border, #ddd)', borderRadius: '8px', padding: '12px' }}>
              <div className="alert alert-info" style={{ marginBottom: '12px' }}>
                Le joueur valide cette étape en se rendant <strong>physiquement</strong> sur le point défini ci-dessous (carte).
                Aucune réponse à saisir : c'est la position GPS qui valide.
              </div>

              <label className="form-label">Rayon de validation : {formData.radius_m} m</label>
              <input
                type="range"
                min="20"
                max="200"
                step="5"
                value={formData.radius_m}
                onChange={(e) => updateField('radius_m', parseInt(e.target.value, 10))}
                disabled={loading}
                style={{ width: '100%' }}
              />
              <p className="form-help">
                Plancher à 20 m pour absorber l'imprécision du GPS en ville. 30–50 m est un bon compromis.
              </p>

              <label className="form-label" style={{ marginTop: '12px' }}>Aide au joueur</label>
              <select
                className="form-select"
                value={formData.reveal_mode}
                onChange={(e) => updateField('reveal_mode', e.target.value)}
                disabled={loading}
              >
                <option value="guided">Guidé — le point est affiché sur la carte</option>
                <option value="hotcold">Chaud / froid — jauge de proximité, sans montrer le point</option>
                <option value="blind">Aveugle — aucune aide, le lieu se déduit de l'énoncé</option>
              </select>
              <p className="form-help">
                En "Chaud / froid" et "Aveugle", la position cible n'est jamais envoyée au téléphone du joueur.
              </p>

              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer', marginTop: '12px' }}>
                <input
                  type="checkbox"
                  checked={formData.auto_validate}
                  onChange={(e) => updateField('auto_validate', e.target.checked)}
                  disabled={loading}
                />
                <span>Validation automatique à l'entrée dans le rayon</span>
              </label>
              <p className="form-help">
                Si décoché, un bouton "Valider ma position" est proposé au joueur au bas de l'étape.
              </p>
            </div>
          )}

          {/* Location avec carte interactive */}
          <LocationPicker
            label={formData.answer_type === 'location' ? 'Point à atteindre * (cliquez sur la carte)' : "Position de l'étape (optionnel)"}
            latitude={formData.latitude ? parseFloat(formData.latitude) : null}
            longitude={formData.longitude ? parseFloat(formData.longitude) : null}
            onLocationChange={(lat, lng) => {
              updateField('latitude', lat);
              updateField('longitude', lng);
            }}
            disabled={loading}
          />

          {/* Show location toggle - only visible if location is set */}
          {(formData.latitude || formData.longitude) && (
            <div className="form-group">
              <label style={{ display: 'flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={formData.show_location}
                  onChange={(e) => updateField('show_location', e.target.checked)}
                  disabled={loading}
                />
                <span>Afficher le point sur la carte au joueur</span>
              </label>
              <p className="form-help">
                Si activé, le joueur pourra voir ce point sur une carte pendant cette étape
              </p>
            </div>
          )}

          {/* Image */}
          <ImageUploader
            label="Image de l'étape (optionnel)"
            currentImageUrl={formData.image_url}
            onImageUploaded={(url) => updateField('image_url', url)}
            currentCredit={formData.image_credit}
            onCreditChange={(credit) => updateField('image_credit', credit)}
            disabled={loading}
          />

          {/* Hints */}
          {formData.answer_type !== 'narration' && (
            <div className="form-group">
              <label className="form-label">Indices</label>
              {formData.hints.map((hint, index) => (
                <div key={index} style={{ display: 'flex', gap: '8px', marginBottom: '8px' }}>
                  <input
                    type="text"
                    className="form-input"
                    value={hint}
                    onChange={(e) => {
                      const newHints = [...formData.hints];
                      newHints[index] = e.target.value;
                      updateField('hints', newHints);
                    }}
                    placeholder={`Indice ${index + 1}`}
                    disabled={loading}
                    style={{ flex: 1 }}
                  />
                  <button
                    type="button"
                    className="btn btn-danger btn-small"
                    onClick={() => {
                      const newHints = formData.hints.filter((_, i) => i !== index);
                      updateField('hints', newHints);
                    }}
                    disabled={loading}
                  >
                    🗑️
                  </button>
                </div>
              ))}
              <button
                type="button"
                className="btn btn-secondary btn-small"
                onClick={() => updateField('hints', [...formData.hints, ''])}
                disabled={loading}
              >
                + Ajouter un indice
              </button>

              {formData.hints.length > 0 && (
                <div className="form-group" style={{ marginTop: '12px' }}>
                  <label className="form-label">Pénalité par indice (minutes)</label>
                  <input
                    type="number"
                    className="form-input"
                    value={formData.hint_penalty}
                    onChange={(e) => updateField('hint_penalty', parseInt(e.target.value) || 0)}
                    min="0"
                    disabled={loading}
                  />
                </div>
              )}
            </div>
          )}

          {/* Actions */}
          <div className="flex gap-2" style={{ marginTop: '24px' }}>
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
              {loading ? 'Sauvegarde...' : isEditing ? '💾 Sauvegarder' : '✅ Créer'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default StepEditor;
