import 'package:flutter/material.dart';

// Services
import '../../services/auth_service.dart';
import '../../services/api/api_service.dart';

// Models
import '../../models/escape_game.dart';

// Core widgets
import '../../core/widgets/creator_feedback_sheet.dart';

// Tutorial
import '../tutorial/tutorial_controller.dart';

// Features - EscapeEditorPage (will be imported from main.dart for now)
import '../../main.dart' show EscapeEditorPage;

/* ============================
   CREATOR PAGE
   - Liste des escapes (admin: tous / user: les siens)
   - Filtrage par statut (admin only)
   - Actions: créer brouillon, soumettre, modération admin
============================ */

class CreatorPage extends StatefulWidget {
  const CreatorPage({super.key});
  @override
  State<CreatorPage> createState() => _CreatorPageState();
}

class _CreatorPageState extends State<CreatorPage> {
  final _api = ApiService.instance;

  Future<List<EscapeGame>>? _future;
  bool _isAdmin = false;
  bool _profileLoading = true; // tant que /me n'est pas prêt
  bool get _roleKnown => !_profileLoading;

  // Filtre par statut (admin seulement)
  // autorisés: {all, draft, submitted, published, rejected}
  String _statusFilter = 'all';

  late final VoidCallback _onTokenChanged;

  // Tutorial Phase 4
  final _listKey = GlobalKey();
  final _createButtonKey = GlobalKey();
  final _feedbackKey = GlobalKey();
  bool _tutorialShown = false;

  @override
  void initState() {
    super.initState();

    _onTokenChanged = () {
      final token = AuthService.instance.tokenNotifier.value;
      if (token == null) {
        setState(() {
          _future = null;
          _profileLoading = false; // pas de profil si pas de token
          _isAdmin = false;
        });
        return;
      }
      // token présent -> charger le profil UNE fois
      setState(() {
        _profileLoading = true;
      });
      _ensureProfileBeforeLoading();
    };

    // écouter UNIQUEMENT les changements de token
    AuthService.instance.tokenNotifier.addListener(_onTokenChanged);
    TutorialController.instance.addListener(_onTutorialChanged);

    // boot initial (au cas où token déjà présent)
    _onTokenChanged();
  }

  @override
  void dispose() {
    AuthService.instance.tokenNotifier.removeListener(_onTokenChanged);
    TutorialController.instance.removeListener(_onTutorialChanged);
    super.dispose();
  }

  void _onTutorialChanged() {
    if (mounted) {
      // Reset le flag si on entre dans la phase creatorPage
      if (TutorialController.instance.currentPhase == TutorialPhase.creatorPage) {
        _tutorialShown = false;
      }
      setState(() {});
      // Ajouter un délai pour s'assurer que le widget est complètement rendu
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkAndShowTutorial();
      });
    }
  }

  /// Lance le tutoriel Phase 4 si conditions remplies
  void _checkAndShowTutorial() {
    if (_tutorialShown) return;
    if (!TutorialController.instance.isActive) return;
    if (TutorialController.instance.currentPhase != TutorialPhase.creatorPage) return;

    // Vérifier si l'utilisateur est connecté
    final token = AuthService.instance.tokenNotifier.value;

    // Vérifier que les widgets sont prêts à être ciblés
    if (token != null) {
      // Le bouton feedback doit toujours être présent
      final feedbackKeyAttached = _feedbackKey.currentContext != null;

      // Le bouton créer n'est visible que pour les non-admins
      // Pour les admins, on vérifie seulement le bouton feedback
      final createKeyAttached = _isAdmin || _createButtonKey.currentContext != null;

      if (!createKeyAttached || !feedbackKeyAttached) {
        // Les widgets ne sont pas encore rendus, réessayer au prochain frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkAndShowTutorial();
        });
        return;
      }
    }

    _tutorialShown = true;

    TutorialController.instance.showCreatorTargets(
      context,
      listKey: _listKey,
      createKey: _createButtonKey,
      feedbackKey: _feedbackKey,
      isLoggedIn: token != null,
      isAdmin: _isAdmin,
      onFinish: () {
        // Tutoriel terminé !
      },
    );
  }

  Future<void> _ensureProfileBeforeLoading() async {
    try {
      await AuthService.instance.ensureProfileLoaded();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAdmin = false;        // défaut: vue user si le profil échoue
        _profileLoading = false; // on retire le loader
      });
      _reload();                 // charge la liste côté user
      return;
    }

    if (!mounted) return;
    setState(() {
      _isAdmin = AuthService.instance.isAdmin; // admin connu
      _profileLoading = false;
    });
    _reload();                                   // charge la bonne liste (admin/user)
  }

  void _reload() {
    final token = AuthService.instance.tokenNotifier.value;
    if (token == null) {
      setState(() => _future = null);
      return;
    }

    // Pour admin : on passe le filtre s'il n'est pas "all".
    // Pour user : on ignore le filtre (le backend renvoie uniquement ses escapes).
    final String? statusParam = (_isAdmin && _statusFilter != 'all') ? _statusFilter : null;

    setState(() {
      _future = _api.fetchCreatorList(status: statusParam);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Vérifier si on doit lancer le tutoriel Phase 4 (même sans connexion)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowTutorial();
    });

    return ValueListenableBuilder<String?>(
      valueListenable: AuthService.instance.tokenNotifier,
      builder: (_, token, __) {
        if (token == null) {
          return const Center(child: Text('Connectez-vous pour accéder au mode créateur.'));
        }

        if (_profileLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        // Garantit qu'une requête est lancée (ex: si /me a échoué)
        if (_future == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _future == null) _reload();
          });
          return const Center(child: CircularProgressIndicator());
        }

        return Column(
          children: [
            // Header + filtres + bouton "Nouveau brouillon"
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _isAdmin ? 'Tous les escapes' : 'Mes escapes',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),

                  // Filtres visibles uniquement pour admin
                  if (_roleKnown && _isAdmin) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _statusFilter,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _statusFilter = v);
                          _reload();
                        },
                        items: const [
                          DropdownMenuItem(value: 'all',       child: Text('Tous')),
                          DropdownMenuItem(value: 'draft',     child: Text('Brouillons')),
                          DropdownMenuItem(value: 'submitted', child: Text('Soumis')),
                          DropdownMenuItem(value: 'published', child: Text('Publiés')),
                          DropdownMenuItem(value: 'rejected',  child: Text('Rejetés')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  // Bouton "Nouveau brouillon" : caché pour admin
                  if (!_isAdmin)
                    Flexible(
                      child: FittedBox(
                        key: _createButtonKey,
                        fit: BoxFit.scaleDown,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Nouveau brouillon'),
                          onPressed: () => _openDraftDialog(context),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            if (_roleKnown && _isAdmin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Filtre: ${{
                      'all': 'Tous',
                      'draft': 'Brouillons',
                      'submitted': 'Soumis',
                      'published': 'Publiés',
                      'rejected': 'Rejetés',
                    }[_statusFilter] ?? _statusFilter}',
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                ),
              ),

            // Liste (avec GlobalKey pour tutoriel - focus sur une partie de la zone)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      // Zone de focus pour le tutoriel (moitié supérieure)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: constraints.maxHeight * 0.5,
                        child: Container(key: _listKey),
                      ),
                      // Liste réelle
                      FutureBuilder<List<EscapeGame>>(
                        future: _future,
                        builder: (ctx, snap) {
                          if (snap.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snap.hasError) {
                            return Center(child: Text('Erreur: ${snap.error}'));
                          }

                          var items = snap.data ?? [];

                          // Filtrage complémentaire côté client pour admin quand _statusFilter != 'all'
                          if (_isAdmin && _statusFilter != 'all') {
                            items = items.where((e) => e.status == _statusFilter).toList();
                          }

                          if (items.isEmpty) {
                            return const Center(child: Text('Aucun escape.'));
                          }

                          return RefreshIndicator(
                            onRefresh: () async => _reload(),
                            child: ListView.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final e = items[i];

                                final human = ({
                                  'draft': 'Brouillon',
                                  'submitted': 'Soumis',
                                  'published': 'Publié',
                                  'rejected': 'Rejeté',
                                }[e.status]) ?? e.status;

                                return ListTile(
                                  title: Text(e.title),
                                  subtitle: Text('${e.city} • durée ${e.durationMinutes} min • statut: $human'),
                                  onTap: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => EscapeEditorPage(escape: e)),
                                    );
                                    _reload();
                                  },
                                  trailing: _isAdmin
                                      ? AdminActions(
                                          escape: e,
                                          roleKnown: _roleKnown,
                                          isAdmin: _isAdmin,
                                          onReload: _reload,
                                        )
                                      : (e.status == 'draft'
                                          ? FilledButton.icon(
                                              icon: const Icon(Icons.send_outlined),
                                              label: const Text('Soumettre'),
                                              onPressed: () async {
                                                final ok = await showDialog<bool>(
                                                  context: context,
                                                  builder: (_) => AlertDialog(
                                                    title: const Text('Soumettre cet escape ?'),
                                                    content: const Text(
                                                      'Il passera en "Soumis" et ne sera plus modifiable jusqu\'à décision.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () => Navigator.pop(context, false),
                                                        child: const Text('Annuler'),
                                                      ),
                                                      FilledButton(
                                                        onPressed: () => Navigator.pop(context, true),
                                                        child: const Text('Soumettre'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (ok != true) return;
                                                try {
                                                  await _api.submitEscape(e.id);
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text('Soumis pour approbation')),
                                                  );
                                                  _reload();
                                                } catch (err) {
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text('Erreur: $err')),
                                                  );
                                                }
                                              },
                                            )
                                          : null),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ),

            // --------- Bouton feedback collé en bas ---------
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  key: _feedbackKey,
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.bug_report_outlined),
                    label: const Text('Envoyer un feedback'),
                    onPressed: () => openCreatorFeedbackSheet(
                      context,
                      page: 'creator_page',
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openDraftDialog(BuildContext context) {
    final durationCtrl = TextEditingController(text: '60');
    final titleCtrl = TextEditingController();
    final cityCtrl = TextEditingController(text: 'Paris');
    final latCtrl = TextEditingController(text: '48.8566');
    final lonCtrl = TextEditingController(text: '2.3522');
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nouveau brouillon'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(decoration: const InputDecoration(labelText: 'Titre'), controller: titleCtrl),
              TextField(decoration: const InputDecoration(labelText: 'Ville'), controller: cityCtrl),
              TextField(decoration: const InputDecoration(labelText: 'Durée (min)'), controller: durationCtrl, keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Latitude'), controller: latCtrl, keyboardType: TextInputType.number)),
                  const SizedBox(width: 8),
                  Expanded(child: TextField(decoration: const InputDecoration(labelText: 'Longitude'), controller: lonCtrl, keyboardType: TextInputType.number)),
                ],
              ),
              TextField(decoration: const InputDecoration(labelText: 'Description (optionnel)'), controller: descCtrl),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () async {
              try {
                final id = await _api.createDraft(
                  title: titleCtrl.text.trim(),
                  city: cityCtrl.text.trim(),
                  latitude: double.tryParse(latCtrl.text.trim()) ?? 0,
                  longitude: double.tryParse(lonCtrl.text.trim()) ?? 0,
                  description: descCtrl.text.trim(),
                  durationMinutes: int.tryParse(durationCtrl.text.trim()) ?? 60,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Brouillon créé (#$id)')));
                _reload();
              } catch (err) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $err')));
              }
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }
}




class AdminActions extends StatefulWidget {
  final EscapeGame escape;
  final bool roleKnown;
  final bool isAdmin;
  final VoidCallback onReload;

  const AdminActions({
    super.key,
    required this.escape,
    required this.roleKnown,
    required this.isAdmin,
    required this.onReload,
  });

  @override
  State<AdminActions> createState() => _AdminActionsState();
}

class _AdminActionsState extends State<AdminActions> {
  bool _busy = false;
  ApiService get _api => ApiService.instance;

  @override
  Widget build(BuildContext context) {
    // Rien si rôle inconnu ou non-admin
    if (!widget.roleKnown || !widget.isAdmin) {
      return const SizedBox.shrink();
    }

    // Nouvelle logique :
    // - Approuver -> seulement quand 'submitted'
    // - Rejeter   -> quand 'submitted' ou 'published'
    final st = widget.escape.status;
    final canApprove = st == 'submitted';
    final canReject  = (st == 'submitted' || st == 'published');

    final buttons = <Widget>[];

    if (canApprove) {
      buttons.add(TextButton(
        onPressed: _busy
            ? null
            : () async {
                setState(() => _busy = true);
                try {
                  // On réutilise l'endpoint publish() qui publie après vérifs backend.
                  await _api.publish(widget.escape.id);
                  // Nettoie un éventuel état local de "refusé"
                  await ApiService.instance.unmarkLocallyRefused(widget.escape.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Escape approuvé et publié')),
                    );
                  }
                  widget.onReload();
                } catch (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $err')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: const Text('Approuver'),
      ));
    }

    if (canReject) {
      buttons.add(TextButton(
        onPressed: _busy
            ? null
            : () async {
                final ctrl = TextEditingController();
                final reason = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Motif de refus'),
                    content: TextField(
                      controller: ctrl,
                      decoration: const InputDecoration(hintText: 'Expliquez brièvement le refus'),
                      minLines: 2,
                      maxLines: 4,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Annuler'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, ctrl.text.trim()),
                        child: const Text('Rejeter'),
                      ),
                    ],
                  ),
                );
                if (reason == null || reason.isEmpty) return;

                setState(() => _busy = true);
                try {
                  await _api.rejectEscape(
                    widget.escape.id,
                    reason,
                    includeStatus: (st == 'published'), // utile seulement si publié
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Escape rejeté')),
                    );
                  }
                  widget.onReload();
                } catch (err) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Erreur: $err')),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              },
        child: const Text('Rejeter'),
      ));
    }

    if (buttons.isEmpty) return const SizedBox.shrink();

    // Petit indicateur si action en cours
    if (_busy) {
      buttons.add(const Padding(
        padding: EdgeInsets.only(left: 8),
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ));
    }

    return Row(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}
