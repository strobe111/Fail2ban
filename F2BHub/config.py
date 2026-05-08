import os

BASE_DIR = os.path.abspath(os.path.dirname(__file__))

class Config:
    SECRET_KEY = os.environ.get("SECRET_KEY", "f2bhub-dev-key-change-in-prod")
    SQLALCHEMY_DATABASE_URI = os.environ.get("DATABASE_URL", f"sqlite:///{os.path.join(BASE_DIR, 'f2bhub.db')}")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    AGENT_API_KEY = os.environ.get("AGENT_API_KEY", "change-me-in-prod")