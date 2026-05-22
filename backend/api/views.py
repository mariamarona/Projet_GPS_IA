from rest_framework import viewsets, status
from rest_framework.response import Response
from rest_framework.decorators import action
from .models import Utilisateur, Module, ZoneGPS, Session, Pointage, AlerteFraude, Inscription
from .serializers import (
    UtilisateurSerializer, ModuleSerializer, ZoneGPSSerializer,
    SessionSerializer, PointageSerializer, AlerteFraudeSerializer, InscriptionSerializer
)


class UtilisateurViewSet(viewsets.ModelViewSet):
    queryset         = Utilisateur.objects.all()
    serializer_class = UtilisateurSerializer


class ModuleViewSet(viewsets.ModelViewSet):
    queryset         = Module.objects.all()
    serializer_class = ModuleSerializer


class ZoneGPSViewSet(viewsets.ModelViewSet):
    queryset         = ZoneGPS.objects.all()
    serializer_class = ZoneGPSSerializer


class SessionViewSet(viewsets.ModelViewSet):
    queryset         = Session.objects.all()
    serializer_class = SessionSerializer


class PointageViewSet(viewsets.ModelViewSet):
    queryset         = Pointage.objects.all()
    serializer_class = PointageSerializer


class AlerteFraudeViewSet(viewsets.ModelViewSet):
    queryset         = AlerteFraude.objects.all()
    serializer_class = AlerteFraudeSerializer


class InscriptionViewSet(viewsets.ModelViewSet):
    queryset         = Inscription.objects.all()
    serializer_class = InscriptionSerializer