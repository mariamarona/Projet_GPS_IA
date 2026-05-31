from rest_framework import viewsets, status
from rest_framework.response import Response
from rest_framework.decorators import action
from rest_framework.permissions import AllowAny
from django.utils import timezone
from django.db.models import Count, Q

from .models import Utilisateur, Module, ZoneGPS, Session, Pointage, AlerteFraude, Inscription
from .serializers import (
    UtilisateurSerializer, ModuleSerializer, ZoneGPSSerializer,
    SessionSerializer, PointageSerializer, AlerteFraudeSerializer, InscriptionSerializer
)
from .utils import calculer_distance_metres
import datetime


# ─────────────────────────────────────────────
#  VIEWSETS DE BASE (CRUD)
# ─────────────────────────────────────────────

class UtilisateurViewSet(viewsets.ModelViewSet):
    queryset           = Utilisateur.objects.all()
    serializer_class   = UtilisateurSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        qs   = super().get_queryset()
        role = self.request.query_params.get('role')
        if role:
            qs = qs.filter(role=role)
        return qs


class ModuleViewSet(viewsets.ModelViewSet):
    queryset           = Module.objects.all()
    serializer_class   = ModuleSerializer
    permission_classes = [AllowAny]


class ZoneGPSViewSet(viewsets.ModelViewSet):
    queryset           = ZoneGPS.objects.all()
    serializer_class   = ZoneGPSSerializer
    permission_classes = [AllowAny]


class AlerteFraudeViewSet(viewsets.ModelViewSet):
    queryset           = AlerteFraude.objects.all()
    serializer_class   = AlerteFraudeSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        qs     = super().get_queryset()
        statut = self.request.query_params.get('statut')
        if statut:
            qs = qs.filter(statut=statut)
        return qs


class InscriptionViewSet(viewsets.ModelViewSet):
    queryset           = Inscription.objects.all()
    serializer_class   = InscriptionSerializer
    permission_classes = [AllowAny]


# ─────────────────────────────────────────────
#  SESSION — CRUD + ENDPOINTS PERSONNALISÉS
# ─────────────────────────────────────────────

class SessionViewSet(viewsets.ModelViewSet):
    queryset           = Session.objects.all()
    serializer_class   = SessionSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        qs        = super().get_queryset()
        module_id = self.request.query_params.get('module_id')
        statut    = self.request.query_params.get('statut')
        date      = self.request.query_params.get('date')
        if module_id:
            qs = qs.filter(module_id=module_id)
        if statut:
            qs = qs.filter(statut=statut)
        if date:
            qs = qs.filter(date=date)
        return qs

    # ── POST /api/sessions/{id}/demarrer/ ────────────────────
    @action(detail=True, methods=['POST'], url_path='demarrer')
    def demarrer(self, request, pk=None):
        """
        Démarre une session — passe le statut à EN_COURS.
        La session doit être PLANIFIE.
        """
        session = self.get_object()

        if session.statut != 'PLANIFIE':
            return Response(
                {'error': f'Impossible de démarrer — statut actuel : {session.statut}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        session.statut = Session.Statut.EN_COURS
        session.save()

        return Response({
            'message':    f'Session {session.module.code} démarrée avec succès',
            'session_id': session.id,
            'statut':     session.statut,
            'module':     session.module.code,
            'zone':       session.zone.nom,
            'heure_debut': str(session.heure_debut),
            'heure_fin':   str(session.heure_fin),
        }, status=status.HTTP_200_OK)

    # ── POST /api/sessions/{id}/terminer/ ────────────────────
    @action(detail=True, methods=['POST'], url_path='terminer')
    def terminer(self, request, pk=None):
        """
        Termine une session — passe le statut à TERMINE.
        La session doit être EN_COURS.
        Retourne un résumé des présences.
        """
        session = self.get_object()

        if session.statut != 'EN_COURS':
            return Response(
                {'error': f'Impossible de terminer — statut actuel : {session.statut}'},
                status=status.HTTP_400_BAD_REQUEST
            )

        session.statut = Session.Statut.TERMINE
        session.save()

        # ── Résumé des présences ─────────────────────────────
        pointages      = Pointage.objects.filter(session=session)
        total_pointes  = pointages.count()
        valides        = pointages.filter(statut='VALIDE').count()
        hors_zone      = pointages.filter(statut='HORS_ZONE').count()

        # Nombre d'inscrits au module
        inscrits = Inscription.objects.filter(
            module=session.module,
            is_active=True
        ).count()

        absents = max(0, inscrits - total_pointes)

        return Response({
            'message':       f'Session {session.module.code} terminée',
            'session_id':    session.id,
            'statut':        session.statut,
            'resume': {
                'inscrits':       inscrits,
                'total_pointes':  total_pointes,
                'valides':        valides,
                'hors_zone':      hors_zone,
                'absents':        absents,
                'taux_presence':  f'{round(valides / inscrits * 100, 1) if inscrits > 0 else 0}%',
            }
        }, status=status.HTTP_200_OK)

    # ── POST /api/sessions/{id}/annuler/ ─────────────────────
    @action(detail=True, methods=['POST'], url_path='annuler')
    def annuler(self, request, pk=None):
        """
        Annule une session — passe le statut à ANNULEE.
        """
        session = self.get_object()

        if session.statut == 'TERMINE':
            return Response(
                {'error': 'Impossible d\'annuler une session déjà terminée'},
                status=status.HTTP_400_BAD_REQUEST
            )

        session.statut = Session.Statut.ANNULEE
        session.save()

        return Response({
            'message':    f'Session {session.module.code} annulée',
            'session_id': session.id,
            'statut':     session.statut,
        }, status=status.HTTP_200_OK)

    # ── GET /api/sessions/{id}/absents/ ──────────────────────
    @action(detail=True, methods=['GET'], url_path='absents')
    def absents(self, request, pk=None):
        """
        Retourne la liste des étudiants absents pour une session.
        Un étudiant est absent s'il est inscrit au module
        mais n'a pas de pointage VALIDE pour cette session.
        """
        session = self.get_object()

        # Étudiants inscrits au module
        inscrits = Inscription.objects.filter(
            module=session.module,
            is_active=True
        ).select_related('etudiant')

        # Étudiants ayant pointé (VALIDE)
        pointes_ids = Pointage.objects.filter(
            session=session,
            statut='VALIDE'
        ).values_list('utilisateur_id', flat=True)

        # Absents = inscrits - pointés
        absents = []
        for inscription in inscrits:
            if inscription.etudiant.id not in pointes_ids:
                absents.append({
                    'id':        str(inscription.etudiant.id),
                    'matricule': inscription.etudiant.matricule,
                    'nom':       inscription.etudiant.nom,
                    'prenom':    inscription.etudiant.prenom,
                    'email':     inscription.etudiant.email,
                })

        return Response({
            'session_id':    session.id,
            'module':        session.module.code,
            'date':          str(session.date),
            'total_inscrits': inscrits.count(),
            'total_absents':  len(absents),
            'absents':        absents,
        }, status=status.HTTP_200_OK)

    # ── GET /api/sessions/aujourd-hui/ ───────────────────────
    @action(detail=False, methods=['GET'], url_path="aujourd-hui")
    def aujourd_hui(self, request):
        """
        Retourne toutes les sessions du jour avec leur statut.
        """
        today    = datetime.date.today()
        sessions = Session.objects.filter(
            date=today
        ).select_related('module', 'zone', 'created_by').order_by('heure_debut')

        data = []
        for s in sessions:
            pointages_count = Pointage.objects.filter(session=s, statut='VALIDE').count()
            data.append({
                'id':             s.id,
                'module':         s.module.code,
                'intitule':       s.module.intitule,
                'zone':           s.zone.nom,
                'date':           str(s.date),
                'heure_debut':    str(s.heure_debut),
                'heure_fin':      str(s.heure_fin),
                'statut':         s.statut,
                'nb_presences':   pointages_count,
            })

        return Response({
            'date':     str(today),
            'total':    len(data),
            'sessions': data,
        }, status=status.HTTP_200_OK)


# ─────────────────────────────────────────────
#  POINTAGE — CRUD + ENDPOINTS PERSONNALISÉS
# ─────────────────────────────────────────────

class PointageViewSet(viewsets.ModelViewSet):
    queryset           = Pointage.objects.all()
    serializer_class   = PointageSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        qs         = super().get_queryset()
        session_id = self.request.query_params.get('session_id')
        user_id    = self.request.query_params.get('utilisateur_id')
        statut     = self.request.query_params.get('statut')
        if session_id:
            qs = qs.filter(session_id=session_id)
        if user_id:
            qs = qs.filter(utilisateur_id=user_id)
        if statut:
            qs = qs.filter(statut=statut)
        return qs

    # ── POST /api/pointages/valider/ ─────────────────────────
    @action(detail=False, methods=['POST'], url_path='valider')
    def valider(self, request):
        utilisateur_id = request.data.get('utilisateur_id')
        session_id     = request.data.get('session_id')
        latitude       = request.data.get('latitude')
        longitude      = request.data.get('longitude')
        precision      = request.data.get('precision_gps_m', None)

        if not all([utilisateur_id, session_id, latitude, longitude]):
            return Response(
                {'error': 'utilisateur_id, session_id, latitude et longitude sont requis'},
                status=status.HTTP_400_BAD_REQUEST
            )

        try:
            utilisateur = Utilisateur.objects.get(id=utilisateur_id)
        except Utilisateur.DoesNotExist:
            return Response({'error': 'Utilisateur non trouvé'}, status=status.HTTP_404_NOT_FOUND)

        try:
            session = Session.objects.select_related('zone').get(id=session_id)
        except Session.DoesNotExist:
            return Response({'error': 'Session non trouvée'}, status=status.HTTP_404_NOT_FOUND)

        if session.statut not in ['EN_COURS', 'PLANIFIEE']:
            return Response(
                {'error': f'Session {session.statut} — pointage impossible'},
                status=status.HTTP_400_BAD_REQUEST
            )

        zone     = session.zone
        distance = calculer_distance_metres(latitude, longitude, zone.latitude, zone.longitude)

        dans_zone       = distance <= float(zone.rayon_m)
        statut_pointage = Pointage.Statut.VALIDE if dans_zone else Pointage.Statut.HORS_ZONE
        est_fraude      = not dans_zone

        pointage = Pointage.objects.create(
            utilisateur     = utilisateur,
            session         = session,
            latitude        = latitude,
            longitude       = longitude,
            precision_gps_m = precision,
            distance_zone_m = round(distance, 2),
            statut          = statut_pointage,
            timestamp       = timezone.now(),
        )

        if est_fraude:
            AlerteFraude.objects.create(
                pointage        = pointage,
                type_fraude     = AlerteFraude.TypeFraude.HORS_ZONE,
                score_ia        = round(min(distance / float(zone.rayon_m), 1.0), 3),
                niveau_severite = AlerteFraude.NiveauSeverite.ELEVE,
                statut          = AlerteFraude.Statut.NON_TRAITEE,
                commentaire     = f'Distance: {round(distance, 1)}m — Zone autorisée: {zone.rayon_m}m'
            )

        return Response({
            'pointage_id':  pointage.id,
            'statut':       statut_pointage,
            'dans_zone':    dans_zone,
            'distance_m':   round(distance, 2),
            'rayon_zone_m': float(zone.rayon_m),
            'est_fraude':   est_fraude,
            'message':      '✅ Pointage validé' if dans_zone else '❌ Hors zone GPS — alerte créée'
        }, status=status.HTTP_201_CREATED)

    # ── GET /api/pointages/stats/ ─────────────────────────────
    @action(detail=False, methods=['GET'], url_path='stats')
    def stats(self, request):
        utilisateur_id = request.query_params.get('utilisateur_id')
        session_id     = request.query_params.get('session_id')

        qs = Pointage.objects.all()
        if utilisateur_id:
            qs = qs.filter(utilisateur_id=utilisateur_id)
        if session_id:
            qs = qs.filter(session_id=session_id)

        total     = qs.count()
        valides   = qs.filter(statut='VALIDE').count()
        hors_zone = qs.filter(statut='HORS_ZONE').count()
        rejetes   = qs.filter(statut='REJETE').count()

        taux_presence = round((valides / total * 100), 1) if total > 0 else 0

        return Response({
            'total':         total,
            'valides':       valides,
            'hors_zone':     hors_zone,
            'rejetes':       rejetes,
            'taux_presence': f'{taux_presence}%',
        }, status=status.HTTP_200_OK)

    # ── GET /api/pointages/par-session/ ──────────────────────
    @action(detail=False, methods=['GET'], url_path='par-session')
    def par_session(self, request):
        session_id = request.query_params.get('session_id')

        if not session_id:
            return Response({'error': 'session_id requis'}, status=status.HTTP_400_BAD_REQUEST)

        pointages = Pointage.objects.filter(
            session_id=session_id
        ).select_related('utilisateur', 'session')

        data = []
        for p in pointages:
            data.append({
                'pointage_id': p.id,
                'etudiant': {
                    'id':        str(p.utilisateur.id),
                    'matricule': p.utilisateur.matricule,
                    'nom':       p.utilisateur.nom,
                    'prenom':    p.utilisateur.prenom,
                },
                'timestamp':  p.timestamp,
                'statut':     p.statut,
                'distance_m': p.distance_zone_m,
                'latitude':   str(p.latitude),
                'longitude':  str(p.longitude),
            })

        return Response({
            'session_id': session_id,
            'total':      len(data),
            'pointages':  data
        }, status=status.HTTP_200_OK)