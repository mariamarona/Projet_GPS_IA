from rest_framework import serializers
from .models import Utilisateur, Module, ZoneGPS, Session, Pointage, AlerteFraude, Inscription
import bcrypt


# ─────────────────────────────────────────────
#  UTILISATEUR
# ─────────────────────────────────────────────
class UtilisateurSerializer(serializers.ModelSerializer):

    class Meta:
        model  = Utilisateur
        fields = ['id', 'matricule', 'nom', 'prenom', 'email',
                  'mot_de_passe', 'role', 'is_active', 'created_at', 'last_login']
        extra_kwargs = {
            'mot_de_passe': {'write_only': True},   # jamais renvoyé en GET
            'id':           {'read_only': True},
            'created_at':   {'read_only': True},
            'last_login':   {'read_only': True},
        }

    def create(self, validated_data):
        # Hashage bcrypt avant sauvegarde
        raw_password = validated_data['mot_de_passe']
        hashed = bcrypt.hashpw(raw_password.encode('utf-8'), bcrypt.gensalt())
        validated_data['mot_de_passe'] = hashed.decode('utf-8')
        return super().create(validated_data)

    def update(self, instance, validated_data):
        if 'mot_de_passe' in validated_data:
            raw_password = validated_data['mot_de_passe']
            hashed = bcrypt.hashpw(raw_password.encode('utf-8'), bcrypt.gensalt())
            validated_data['mot_de_passe'] = hashed.decode('utf-8')
        return super().update(instance, validated_data)


# ─────────────────────────────────────────────
#  MODULE
# ─────────────────────────────────────────────
class ModuleSerializer(serializers.ModelSerializer):
    enseignant_nom = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model  = Module
        fields = ['id', 'code', 'intitule', 'enseignant', 'enseignant_nom',
                  'seuil_presence_pct', 'created_at']
        extra_kwargs = {'created_at': {'read_only': True}}

    def get_enseignant_nom(self, obj):
        return f"{obj.enseignant.prenom} {obj.enseignant.nom}"


# ─────────────────────────────────────────────
#  ZONE GPS
# ─────────────────────────────────────────────
class ZoneGPSSerializer(serializers.ModelSerializer):

    class Meta:
        model  = ZoneGPS
        fields = ['id', 'nom', 'latitude', 'longitude', 'rayon_m', 'created_at', 'updated_at']
        extra_kwargs = {
            'created_at': {'read_only': True},
            'updated_at': {'read_only': True},
        }


# ─────────────────────────────────────────────
#  SESSION
# ─────────────────────────────────────────────
class SessionSerializer(serializers.ModelSerializer):
    module_code = serializers.SerializerMethodField(read_only=True)
    zone_nom    = serializers.SerializerMethodField(read_only=True)

    class Meta:
        model  = Session
        fields = ['id', 'module', 'module_code', 'zone', 'zone_nom',
                  'date', 'heure_debut', 'heure_fin', 'statut', 'created_by']

    def get_module_code(self, obj):
        return obj.module.code

    def get_zone_nom(self, obj):
        return obj.zone.nom


# ─────────────────────────────────────────────
#  POINTAGE
# ─────────────────────────────────────────────
class PointageSerializer(serializers.ModelSerializer):

    class Meta:
        model  = Pointage
        fields = ['id', 'utilisateur', 'session', 'timestamp',
                  'latitude', 'longitude', 'precision_gps_m',
                  'distance_zone_m', 'is_offline_sync', 'offline_sync_at', 'statut']
        extra_kwargs = {'timestamp': {'read_only': True}}


# ─────────────────────────────────────────────
#  ALERTE FRAUDE
# ─────────────────────────────────────────────
class AlerteFraudeSerializer(serializers.ModelSerializer):

    class Meta:
        model  = AlerteFraude
        fields = ['id', 'pointage', 'type_fraude', 'score_ia',
                  'niveau_severite', 'statut', 'traite_par',
                  'commentaire', 'timestamp', 'traite_at']
        extra_kwargs = {'timestamp': {'read_only': True}}


# ─────────────────────────────────────────────
#  INSCRIPTION
# ─────────────────────────────────────────────
class InscriptionSerializer(serializers.ModelSerializer):

    class Meta:
        model  = Inscription
        fields = ['id', 'etudiant', 'module', 'date_inscription', 'is_active']