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


class InscriptionViewSet(viewsets.ModelViewSet):
    queryset           = Inscription.objects.all()
    serializer_class   = InscriptionSerializer
    permission_classes = [AllowAny]


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

    @action(detail=True, methods=['POST'], url_path='demarrer')
    def demarrer(self, request, pk=None):
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

    @action(detail=True, methods=['POST'], url_path='terminer')
    def terminer(self, request, pk=None):
        session = self.get_object()
        if session.statut != 'EN_COURS':
            return Response(
                {'error': f'Impossible de terminer — statut actuel : {session.statut}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        session.statut = Session.Statut.TERMINE
        session.save()
        pointages     = Pointage.objects.filter(session=session)
        total_pointes = pointages.count()
        valides       = pointages.filter(statut='VALIDE').count()
        hors_zone     = pointages.filter(statut='HORS_ZONE').count()
        inscrits      = Inscription.objects.filter(module=session.module, is_active=True).count()
        absents       = max(0, inscrits - total_pointes)
        return Response({
            'message':    f'Session {session.module.code} terminée',
            'session_id': session.id,
            'statut':     session.statut,
            'resume': {
                'inscrits':      inscrits,
                'total_pointes': total_pointes,
                'valides':       valides,
                'hors_zone':     hors_zone,
                'absents':       absents,
                'taux_presence': f'{round(valides / inscrits * 100, 1) if inscrits > 0 else 0}%',
            }
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['POST'], url_path='annuler')
    def annuler(self, request, pk=None):
        session = self.get_object()
        if session.statut == 'TERMINE':
            return Response(
                {'error': "Impossible d'annuler une session déjà terminée"},
                status=status.HTTP_400_BAD_REQUEST
            )
        session.statut = Session.Statut.ANNULEE
        session.save()
        return Response({
            'message':    f'Session {session.module.code} annulée',
            'session_id': session.id,
            'statut':     session.statut,
        }, status=status.HTTP_200_OK)

    @action(detail=True, methods=['GET'], url_path='absents')
    def absents(self, request, pk=None):
        session  = self.get_object()
        inscrits = Inscription.objects.filter(module=session.module, is_active=True).select_related('etudiant')
        pointes_ids = Pointage.objects.filter(session=session, statut='VALIDE').values_list('utilisateur_id', flat=True)
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
            'session_id':     session.id,
            'module':         session.module.code,
            'date':           str(session.date),
            'total_inscrits': inscrits.count(),
            'total_absents':  len(absents),
            'absents':        absents,
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['GET'], url_path="aujourd-hui")
    def aujourd_hui(self, request):
        today    = datetime.date.today()
        sessions = Session.objects.filter(date=today).select_related('module', 'zone', 'created_by').order_by('heure_debut')
        data = []
        for s in sessions:
            nb = Pointage.objects.filter(session=s, statut='VALIDE').count()
            data.append({
                'id':           s.id,
                'module':       s.module.code,
                'intitule':     s.module.intitule,
                'zone':         s.zone.nom,
                'date':         str(s.date),
                'heure_debut':  str(s.heure_debut),
                'heure_fin':    str(s.heure_fin),
                'statut':       s.statut,
                'nb_presences': nb,
            })
        return Response({'date': str(today), 'total': len(data), 'sessions': data}, status=status.HTTP_200_OK)


class AlerteFraudeViewSet(viewsets.ModelViewSet):
    queryset           = AlerteFraude.objects.all()
    serializer_class   = AlerteFraudeSerializer
    permission_classes = [AllowAny]

    def get_queryset(self):
        qs              = super().get_queryset()
        statut          = self.request.query_params.get('statut')
        type_fraude     = self.request.query_params.get('type_fraude')
        niveau_severite = self.request.query_params.get('niveau_severite')
        utilisateur_id  = self.request.query_params.get('utilisateur_id')
        if statut:
            qs = qs.filter(statut=statut)
        if type_fraude:
            qs = qs.filter(type_fraude=type_fraude)
        if niveau_severite:
            qs = qs.filter(niveau_severite=niveau_severite)
        if utilisateur_id:
            qs = qs.filter(pointage__utilisateur_id=utilisateur_id)
        return qs

    @action(detail=True, methods=['PATCH'], url_path='traiter')
    def traiter(self, request, pk=None):
        alerte      = self.get_object()
        statut      = request.data.get('statut')
        traite_par  = request.data.get('traite_par')
        commentaire = request.data.get('commentaire', None)

        statuts_valides = ['EN_INVESTIGATION', 'FRAUDE_CONFIRMEE', 'FAUSSE_ALERTE']
        if not statut or statut not in statuts_valides:
            return Response(
                {'error': f'Statut invalide. Choisir parmi : {statuts_valides}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        if alerte.statut in ['FRAUDE_CONFIRMEE', 'FAUSSE_ALERTE']:
            return Response(
                {'error': f'Alerte déjà traitée — statut : {alerte.statut}'},
                status=status.HTTP_400_BAD_REQUEST
            )
        alerte.statut = statut
        if commentaire:
            alerte.commentaire = commentaire
        if traite_par:
            try:
                admin = Utilisateur.objects.get(id=traite_par)
                alerte.traite_par = admin
            except Utilisateur.DoesNotExist:
                pass
        if statut in ['FRAUDE_CONFIRMEE', 'FAUSSE_ALERTE']:
            alerte.traite_at = timezone.now()
        alerte.save()
        return Response({
            'message':     f'Alerte mise à jour → {statut}',
            'alerte_id':   alerte.id,
            'statut':      alerte.statut,
            'traite_at':   alerte.traite_at,
            'commentaire': alerte.commentaire,
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['GET'], url_path='non-traitees')
    def non_traitees(self, request):
        alertes = AlerteFraude.objects.filter(
            statut='NON_TRAITEE'
        ).select_related(
            'pointage__utilisateur',
            'pointage__session__module',
            'pointage__session__zone'
        ).order_by('-timestamp')

        data = []
        for a in alertes:
            p = a.pointage
            data.append({
                'alerte_id':       a.id,
                'type_fraude':     a.type_fraude,
                'niveau_severite': a.niveau_severite,
                'score_ia':        a.score_ia,
                'timestamp':       a.timestamp,
                'etudiant': {
                    'id':        str(p.utilisateur.id),
                    'matricule': p.utilisateur.matricule,
                    'nom':       p.utilisateur.nom,
                    'prenom':    p.utilisateur.prenom,
                },
                'session': {
                    'id':     p.session.id,
                    'module': p.session.module.code,
                    'date':   str(p.session.date),
                    'zone':   p.session.zone.nom,
                },
                'pointage': {
                    'id':         p.id,
                    'latitude':   str(p.latitude),
                    'longitude':  str(p.longitude),
                    'distance_m': p.distance_zone_m,
                    'timestamp':  p.timestamp,
                }
            })
        return Response({'total': len(data), 'alertes': data}, status=status.HTTP_200_OK)

    @action(detail=False, methods=['GET'], url_path='dashboard')
    def dashboard(self, request):
        total            = AlerteFraude.objects.count()
        non_traitees     = AlerteFraude.objects.filter(statut='NON_TRAITEE').count()
        en_investigation = AlerteFraude.objects.filter(statut='EN_INVESTIGATION').count()
        confirmees       = AlerteFraude.objects.filter(statut='FRAUDE_CONFIRMEE').count()
        fausses_alertes  = AlerteFraude.objects.filter(statut='FAUSSE_ALERTE').count()
        par_type = {}
        for t in AlerteFraude.TypeFraude:
            c = AlerteFraude.objects.filter(type_fraude=t.value).count()
            if c > 0:
                par_type[t.value] = c
        par_severite = {}
        for n in AlerteFraude.NiveauSeverite:
            c = AlerteFraude.objects.filter(niveau_severite=n.value).count()
            if c > 0:
                par_severite[n.value] = c
        return Response({
            'total':            total,
            'non_traitees':     non_traitees,
            'en_investigation': en_investigation,
            'confirmees':       confirmees,
            'fausses_alertes':  fausses_alertes,
            'par_type':         par_type,
            'par_severite':     par_severite,
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['GET'], url_path='par-etudiant')
    def par_etudiant(self, request):
        utilisateur_id = request.query_params.get('utilisateur_id')
        if not utilisateur_id:
            return Response({'error': 'utilisateur_id requis'}, status=status.HTTP_400_BAD_REQUEST)
        alertes = AlerteFraude.objects.filter(
            pointage__utilisateur_id=utilisateur_id
        ).select_related('pointage__session__module').order_by('-timestamp')
        data = []
        for a in alertes:
            data.append({
                'alerte_id':       a.id,
                'type_fraude':     a.type_fraude,
                'niveau_severite': a.niveau_severite,
                'score_ia':        a.score_ia,
                'statut':          a.statut,
                'timestamp':       a.timestamp,
                'traite_at':       a.traite_at,
                'commentaire':     a.commentaire,
                'module':          a.pointage.session.module.code,
                'date_session':    str(a.pointage.session.date),
            })
        return Response({
            'utilisateur_id': utilisateur_id,
            'total':          len(data),
            'alertes':        data,
        }, status=status.HTTP_200_OK)


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
        if session.statut not in ['EN_COURS', 'PLANIFIE']:
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
            utilisateur=utilisateur, session=session,
            latitude=latitude, longitude=longitude,
            precision_gps_m=precision,
            distance_zone_m=round(distance, 2),
            statut=statut_pointage,
            timestamp=timezone.now(),
        )
        if est_fraude:
            AlerteFraude.objects.create(
                pointage=pointage,
                type_fraude=AlerteFraude.TypeFraude.HORS_ZONE,
                score_ia=round(min(distance / float(zone.rayon_m), 1.0), 3),
                niveau_severite=AlerteFraude.NiveauSeverite.ELEVE,
                statut=AlerteFraude.Statut.NON_TRAITEE,
                commentaire=f'Distance: {round(distance, 1)}m — Zone autorisée: {zone.rayon_m}m'
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
        taux      = round((valides / total * 100), 1) if total > 0 else 0
        return Response({
            'total':         total,
            'valides':       valides,
            'hors_zone':     hors_zone,
            'rejetes':       rejetes,
            'taux_presence': f'{taux}%',
        }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['GET'], url_path='par-session')
    def par_session(self, request):
        session_id = request.query_params.get('session_id')
        if not session_id:
            return Response({'error': 'session_id requis'}, status=status.HTTP_400_BAD_REQUEST)
        pointages = Pointage.objects.filter(session_id=session_id).select_related('utilisateur', 'session')
        data = []
        for p in pointages:
            data.append({
                'pointage_id': p.id,
                'etudiant': {
                    'id': str(p.utilisateur.id),
                    'matricule': p.utilisateur.matricule,
                    'nom': p.utilisateur.nom,
                    'prenom': p.utilisateur.prenom,
                },
                'timestamp':  p.timestamp,
                'statut':     p.statut,
                'distance_m': p.distance_zone_m,
                'latitude':   str(p.latitude),
                'longitude':  str(p.longitude),
            })
        return Response({'session_id': session_id, 'total': len(data), 'pointages': data}, status=status.HTTP_200_OK)