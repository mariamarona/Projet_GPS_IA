import uuid
from django.db import models
from django.utils import timezone


# ─────────────────────────────────────────────
#  UTILISATEUR
# ─────────────────────────────────────────────
class Utilisateur(models.Model):

    class Role(models.TextChoices):
        STUDENT     = 'STUDENT',     'Étudiant'
        TEACHER     = 'TEACHER',     'Enseignant'
        ADMIN       = 'ADMIN',       'Administrateur'
        SUPER_ADMIN = 'SUPER_ADMIN', 'Super Administrateur'

    id           = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    matricule    = models.CharField(max_length=50, unique=True)
    nom          = models.CharField(max_length=100)
    prenom       = models.CharField(max_length=100)
    email        = models.EmailField(unique=True)
    mot_de_passe = models.CharField(max_length=255)
    role         = models.CharField(max_length=15, choices=Role.choices, default=Role.STUDENT)
    is_active    = models.BooleanField(default=True)
    created_at   = models.DateTimeField(auto_now_add=True)
    last_login   = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'utilisateur'

    def __str__(self):
        return f"{self.matricule} – {self.prenom} {self.nom}"


# ─────────────────────────────────────────────
#  MODULE
# ─────────────────────────────────────────────
class Module(models.Model):

    code       = models.CharField(max_length=20, unique=True)
    intitule   = models.CharField(max_length=200)
    enseignant = models.ForeignKey(
        Utilisateur,
        on_delete=models.PROTECT,
        related_name='modules_enseignes'
    )
    seuil_presence_pct = models.PositiveSmallIntegerField(default=75)
    created_at         = models.DateTimeField(auto_now_add=True)

    class Meta:
        db_table = 'module'

    def __str__(self):
        return f"{self.code} – {self.intitule}"


# ─────────────────────────────────────────────
#  ZONE GPS
# ─────────────────────────────────────────────
class ZoneGPS(models.Model):

    nom       = models.CharField(max_length=150, unique=True)
    latitude  = models.DecimalField(max_digits=9, decimal_places=6)
    longitude = models.DecimalField(max_digits=9, decimal_places=6)
    rayon_m   = models.IntegerField()
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        db_table = 'zone_gps'

    def __str__(self):
        return f"{self.nom} (rayon: {self.rayon_m}m)"


# ─────────────────────────────────────────────
#  SESSION
# ─────────────────────────────────────────────
class Session(models.Model):

    class Statut(models.TextChoices):
        PLANIFIE = 'PLANIFIE', 'Planifié'
        EN_COURS  = 'EN_COURS',  'En cours'
        TERMINE  = 'TERMINE',  'Terminé'
        ANNULEE   = 'ANNULEE',   'Annulée'

    module      = models.ForeignKey(Module,  on_delete=models.CASCADE,  related_name='sessions')
    zone        = models.ForeignKey(ZoneGPS, on_delete=models.PROTECT,  related_name='sessions')
    created_by  = models.ForeignKey(Utilisateur, on_delete=models.PROTECT, related_name='sessions_creees')
    date        = models.DateField()
    heure_debut = models.TimeField()
    heure_fin   = models.TimeField()
    statut      = models.CharField(max_length=12, choices=Statut.choices, default=Statut.PLANIFIE)

    class Meta:
        db_table = 'session'
        constraints = [
            models.UniqueConstraint(
                fields=['module', 'zone', 'date', 'heure_debut', 'heure_fin'],
                name='unique_session_module_zone_creneau'
            )
        ]

    def __str__(self):
        return f"{self.module.code} – {self.date} {self.heure_debut}→{self.heure_fin}"


# ─────────────────────────────────────────────
#  POINTAGE
# ─────────────────────────────────────────────
class Pointage(models.Model):

    class Statut(models.TextChoices):
        VALIDE    = 'VALIDE',    'Valide'
        HORS_ZONE = 'HORS_ZONE', 'Hors zone'
        REJETE    = 'REJETE',    'Rejeté'

    utilisateur     = models.ForeignKey(Utilisateur, on_delete=models.PROTECT, related_name='pointages')
    session         = models.ForeignKey(Session,     on_delete=models.PROTECT, related_name='pointages')
    timestamp       = models.DateTimeField(default=timezone.now)
    latitude        = models.DecimalField(max_digits=9, decimal_places=6)
    longitude       = models.DecimalField(max_digits=9, decimal_places=6)
    precision_gps_m = models.FloatField(null=True, blank=True)
    distance_zone_m = models.FloatField(null=True, blank=True)
    is_offline_sync = models.BooleanField(default=False)
    offline_sync_at = models.DateTimeField(null=True, blank=True)
    statut          = models.CharField(max_length=10, choices=Statut.choices, default=Statut.VALIDE)

    class Meta:
        db_table = 'pointage'
        indexes = [
            models.Index(fields=['session', 'timestamp'],   name='idx_pointage_session_ts'),
            models.Index(fields=['utilisateur', 'session'], name='idx_pointage_user_session'),
        ]

    def __str__(self):
        return f"Pointage {self.utilisateur.matricule} – {self.session} [{self.statut}]"


# ─────────────────────────────────────────────
#  ALERTE FRAUDE
# ─────────────────────────────────────────────
class AlerteFraude(models.Model):

    class TypeFraude(models.TextChoices):
        HORS_ZONE      = 'hors_zone',      'Hors zone GPS'
        DOUBLON        = 'doublon',         'Pointage en double'
        COORDS_FIXES   = 'coords_fixes',    'Coordonnées GPS fixes'
        HEURE_INVALIDE = 'heure_invalide',  'Heure hors session'
        AUTRE          = 'autre',           'Autre'

    class NiveauSeverite(models.TextChoices):
        FAIBLE   = 'FAIBLE',   'Faible'
        MOYEN    = 'MOYEN',    'Moyen'
        ELEVE    = 'ELEVE',    'Élevé'
        CRITIQUE = 'CRITIQUE', 'Critique'

    class Statut(models.TextChoices):
        NON_TRAITEE      = 'NON_TRAITEE',      'Non traitée'
        EN_INVESTIGATION = 'EN_INVESTIGATION',  'En investigation'
        FRAUDE_CONFIRMEE = 'FRAUDE_CONFIRMEE',  'Fraude confirmée'
        FAUSSE_ALERTE    = 'FAUSSE_ALERTE',     'Fausse alerte'

    pointage        = models.OneToOneField(Pointage, on_delete=models.PROTECT, related_name='alerte_fraude')
    type_fraude     = models.CharField(max_length=20, choices=TypeFraude.choices)
    score_ia        = models.FloatField(null=True, blank=True)
    niveau_severite = models.CharField(max_length=10, choices=NiveauSeverite.choices, null=True, blank=True)
    statut          = models.CharField(max_length=20, choices=Statut.choices, default=Statut.NON_TRAITEE)
    traite_par      = models.ForeignKey(Utilisateur, on_delete=models.SET_NULL, null=True, blank=True, related_name='alertes_traitees')
    commentaire     = models.TextField(blank=True, null=True)
    timestamp       = models.DateTimeField(auto_now_add=True)
    traite_at       = models.DateTimeField(null=True, blank=True)

    class Meta:
        db_table = 'alerte_fraude'
        indexes = [
            models.Index(fields=['statut', 'timestamp'], name='idx_alerte_statut_ts'),
        ]

    def __str__(self):
        return f"Alerte {self.type_fraude} – {self.statut}"


# ─────────────────────────────────────────────
#  INSCRIPTION  (N-N Étudiant ↔ Module)
# ─────────────────────────────────────────────
class Inscription(models.Model):

    etudiant         = models.ForeignKey(Utilisateur, on_delete=models.CASCADE, related_name='inscriptions')
    module           = models.ForeignKey(Module,      on_delete=models.CASCADE, related_name='inscriptions')
    date_inscription = models.DateField(default=timezone.now)
    is_active        = models.BooleanField(default=True)

    class Meta:
        db_table = 'inscription'
        constraints = [
            models.UniqueConstraint(fields=['etudiant', 'module'], name='unique_inscription_etudiant_module')
        ]

    def __str__(self):
        return f"{self.etudiant.matricule} → {self.module.code}"