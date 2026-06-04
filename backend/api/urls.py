from rest_framework.routers import DefaultRouter
from django.urls import path, include
from .views import (
    UtilisateurViewSet, ModuleViewSet, ZoneGPSViewSet,
    SessionViewSet, PointageViewSet, AlerteFraudeViewSet, InscriptionViewSet
)
from .auth_views import login, logout, refresh_token, change_password

router = DefaultRouter()
router.register(r'utilisateurs', UtilisateurViewSet)
router.register(r'modules',      ModuleViewSet)
router.register(r'zones',        ZoneGPSViewSet)
router.register(r'sessions',     SessionViewSet)
router.register(r'pointages',    PointageViewSet)
router.register(r'alertes',      AlerteFraudeViewSet)
router.register(r'inscriptions', InscriptionViewSet)

urlpatterns = [
    # ── Auth ────────────────────────────────────
    path('auth/login/',           login,           name='login'),
    path('auth/logout/',          logout,          name='logout'),
    path('auth/refresh/',         refresh_token,   name='refresh'),
    path('auth/change-password/', change_password, name='change-password'),

    # ── Entités ─────────────────────────────────
    path('', include(router.urls)),
]