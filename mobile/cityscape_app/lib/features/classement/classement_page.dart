// lib/features/classement/classement_page.dart
//
// Classement des meilleurs temps sur une escape.

import 'package:flutter/material.dart';

import '../../models/classement.dart';
import '../../services/api/api_service.dart';

class ClassementPage extends StatefulWidget {
  final int escapeId;
  final String titreEscape;

  const ClassementPage({
    super.key,
    required this.escapeId,
    required this.titreEscape,
  });

  @override
  State<ClassementPage> createState() => _ClassementPageState();
}

class _ClassementPageState extends State<ClassementPage> {
  late Future<Classement> _chargement;

  @override
  void initState() {
    super.initState();
    _chargement = _charger();
  }

  Future<Classement> _charger() =>
      ApiService.instance.fetchClassement(widget.escapeId);

  Future<void> _rafraichir() async {
    final f = _charger();
    setState(() => _chargement = f);
    await f.catchError((_) => const Classement(
          escapeId: 0, totalClasses: 0, entrees: [],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Classement'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.titreEscape,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: FutureBuilder<Classement>(
        future: _chargement,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _Erreur(onReessayer: _rafraichir);
          }
          final c = snap.data;
          if (c == null || c.estVide) {
            return _Vide(onRafraichir: _rafraichir);
          }
          return _Liste(classement: c, onRafraichir: _rafraichir);
        },
      ),
    );
  }
}

class _Erreur extends StatelessWidget {
  final Future<void> Function() onReessayer;
  const _Erreur({required this.onReessayer});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.black38),
            const SizedBox(height: 12),
            const Text(
              'Impossible de charger le classement.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReessayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un classement vide n'est pas une erreur : c'est l'etat normal d'une escape
/// que personne n'a encore terminee depuis la mise en place du chronometrage.
class _Vide extends StatelessWidget {
  final Future<void> Function() onRafraichir;
  const _Vide({required this.onRafraichir});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRafraichir,
      child: ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.emoji_events_outlined, size: 56, color: Colors.black26),
          SizedBox(height: 16),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Personne n\'a encore terminé cette escape.\n'
              'La première place est à prendre.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}

class _Liste extends StatelessWidget {
  final Classement classement;
  final Future<void> Function() onRafraichir;

  const _Liste({required this.classement, required this.onRafraichir});

  @override
  Widget build(BuildContext context) {
    final moi = classement.moi;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: onRafraichir,
            child: ListView.separated(
              itemCount: classement.entrees.length + 1,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Text(
                      classement.totalClasses == 1
                          ? '1 partie terminée'
                          : '${classement.totalClasses} parties terminées',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  );
                }
                final e = classement.entrees[i - 1];
                return _Ligne(
                  entree: e,
                  // Mettre en valeur la ligne du joueur, pour qu'il se
                  // retrouve dans la liste sans la parcourir.
                  estMoi: moi != null && e.rang == moi.rang,
                );
              },
            ),
          ),
        ),
        // Le joueur est classé mais hors du haut du tableau : sa ligne reste
        // visible en bas, c'est l'information qui l'intéresse.
        if (moi != null && !classement.moiDejaDansLaListe)
          Material(
            elevation: 8,
            child: SafeArea(
              top: false,
              child: _Ligne(entree: moi, estMoi: true, suffixe: 'sur ${classement.totalClasses}'),
            ),
          ),
      ],
    );
  }
}

class _Ligne extends StatelessWidget {
  final EntreeClassement entree;
  final bool estMoi;
  final String? suffixe;

  const _Ligne({required this.entree, this.estMoi = false, this.suffixe});

  /// Les trois premiers rangs sont distingués ; au-delà, le numéro suffit.
  Widget _insigneRang(BuildContext context) {
    const medailles = {1: '🥇', 2: '🥈', 3: '🥉'};
    final medaille = medailles[entree.rang];
    if (medaille != null) {
      return Text(medaille, style: const TextStyle(fontSize: 22));
    }
    return SizedBox(
      width: 28,
      child: Text(
        '${entree.rang}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: estMoi ? theme.colorScheme.primary.withValues(alpha: 0.08) : null,
      child: ListTile(
        leading: _insigneRang(context),
        title: Row(
          children: [
            Flexible(
              child: Text(
                entree.joueur,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: estMoi ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (estMoi) ...[
              const SizedBox(width: 6),
              const Text('(vous)', style: TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ],
        ),
        subtitle: entree.aUnePenalite
            // On détaille quand il y a une pénalité, pour que le score ne
            // paraisse pas incohérent avec le temps de jeu affiché.
            ? Text(
                '${formaterDuree(entree.tempsSecondes)} '
                '+ ${formaterDuree(entree.penaliteSecondes)} de pénalité',
                style: const TextStyle(fontSize: 12),
              )
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formaterDuree(entree.scoreSecondes),
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (suffixe != null)
              Text(suffixe!, style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
