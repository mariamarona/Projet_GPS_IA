from rest_framework.routers import DefaultRouter
from django.urls import path, include
from .views import (
    UtilisateurViewSet, ModuleViewSet, ZoneGPSViewSet,
    SessionViewSet, PointageViewSet, AlerteFraudeViewSet, InscriptionViewSet
)

router = DefaultRouter()
router.register(r'utilisateurs', UtilisateurViewSet)
router.register(r'modules',      ModuleViewSet)
router.register(r'zones',        ZoneGPSViewSet)
router.register(r'sessions',     SessionViewSet)
router.register(r'pointages',    PointageViewSet)
router.register(r'alertes',      AlerteFraudeViewSet)
router.register(r'inscriptions', InscriptionViewSet)

urlpatterns = [
    path('', include(router.urls)),
]