import os
import sys
import csv
import io
from datetime import datetime, date, timedelta
from typing import Optional, List
from pathlib import Path

from fastapi import FastAPI, HTTPException, Depends, status, Query, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, Response, RedirectResponse
from fastapi.encoders import jsonable_encoder
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, Field
from sqlalchemy import create_engine, Column, Integer, String, Text, Date, DateTime, ForeignKey, Boolean, Float, or_
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, Session, relationship
from passlib.context import CryptContext
from jose import JWTError, jwt
import shutil

# ============== Configuration ==============
BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("DRMEDHAT_DATA_DIR", BASE_DIR / "data"))
STATIC_DIR = BASE_DIR / "static"
DATABASE_PATH = DATA_DIR / "clinic.db"

SECRET_KEY = os.environ.get("SECRET_KEY", "clinic-secret-key-local-2024")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_DAYS = 7

# Default password: clinic123
DEFAULT_PASSWORD_HASH = "$2b$12$T94Qan8NG4EM.7.hL.7Ae.eYHc1O409nrzapjn/SFu.gzbSV17Fa."
DOCTOR_PASSWORD_HASH = os.environ.get("DOCTOR_PASSWORD_HASH", DEFAULT_PASSWORD_HASH)

# ============== Database Setup ==============
DATA_DIR.mkdir(exist_ok=True)
engine = create_engine(f"sqlite:///{DATABASE_PATH}", connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

# ============== Models ==============
class Patient(Base):
    __tablename__ = "patients"
    id = Column(Integer, primary_key=True, index=True)
    full_name = Column(String(255), nullable=False, index=True)
    date_of_birth = Column(Date, nullable=False)
    phone = Column(String(50), nullable=True, index=True)
    allergies = Column(Text, nullable=True)
    chronic_conditions = Column(Text, nullable=True)
    medications = Column(Text, nullable=True)
    medical_history_notes = Column(Text, nullable=True)
    is_deleted = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    visits = relationship("Visit", back_populates="patient", order_by="desc(Visit.visit_date)")

class Visit(Base):
    __tablename__ = "visits"
    id = Column(Integer, primary_key=True, index=True)
    patient_id = Column(Integer, ForeignKey("patients.id"), nullable=False)
    visit_date = Column(Date, nullable=False, default=date.today)
    is_first_visit = Column(Boolean, default=False)
    chief_complaint = Column(Text, nullable=True)
    history_of_present_illness = Column(Text, nullable=True)
    past_medical_history = Column(Text, nullable=True)
    blood_pressure_systolic = Column(Integer, nullable=True)
    blood_pressure_diastolic = Column(Integer, nullable=True)
    temperature = Column(Float, nullable=True)
    oxygen_saturation = Column(Integer, nullable=True)
    pulse = Column(Integer, nullable=True)
    local_examination = Column(Text, nullable=True)
    investigations = Column(Text, nullable=True)
    primary_diagnosis = Column(Text, nullable=True)
    secondary_diagnosis = Column(Text, nullable=True)
    medications_prescribed = Column(Text, nullable=True)
    treatment_plan = Column(Text, nullable=True)
    follow_up_instructions = Column(Text, nullable=True)
    notes = Column(Text, nullable=True)
    complaint = Column(Text, nullable=True)
    examination_notes = Column(Text, nullable=True)
    diagnosis = Column(Text, nullable=True)
    plan_notes = Column(Text, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    patient = relationship("Patient", back_populates="visits")

Base.metadata.create_all(bind=engine)

# ============== Serialization Helpers ==============
PATIENT_FIELDS = [
    "id",
    "full_name",
    "date_of_birth",
    "phone",
    "allergies",
    "chronic_conditions",
    "medications",
    "medical_history_notes",
    "is_deleted",
    "created_at",
    "updated_at",
]

VISIT_FIELDS = [
    "id",
    "patient_id",
    "visit_date",
    "is_first_visit",
    "chief_complaint",
    "history_of_present_illness",
    "past_medical_history",
    "blood_pressure_systolic",
    "blood_pressure_diastolic",
    "temperature",
    "oxygen_saturation",
    "pulse",
    "local_examination",
    "investigations",
    "primary_diagnosis",
    "secondary_diagnosis",
    "medications_prescribed",
    "treatment_plan",
    "follow_up_instructions",
    "notes",
    "complaint",
    "examination_notes",
    "diagnosis",
    "plan_notes",
    "created_at",
    "updated_at",
]

def serialize_visit(visit: Visit) -> dict:
    return {field: getattr(visit, field) for field in VISIT_FIELDS}

def serialize_patient(patient: Patient) -> dict:
    data = {field: getattr(patient, field) for field in PATIENT_FIELDS}
    data["visits"] = [serialize_visit(v) for v in patient.visits]
    return jsonable_encoder(data)

# ============== Schemas ==============
class LoginRequest(BaseModel):
    password: str

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"

class FirstVisitCreate(BaseModel):
    visit_date: date
    chief_complaint: str = Field(..., min_length=1)
    history_of_present_illness: Optional[str] = None
    past_medical_history: Optional[str] = None
    blood_pressure_systolic: Optional[int] = None
    blood_pressure_diastolic: Optional[int] = None
    temperature: Optional[float] = None
    oxygen_saturation: Optional[int] = None
    pulse: Optional[int] = None
    local_examination: Optional[str] = None
    investigations: Optional[str] = None
    primary_diagnosis: Optional[str] = None
    secondary_diagnosis: Optional[str] = None
    medications_prescribed: Optional[str] = None
    treatment_plan: Optional[str] = None
    follow_up_instructions: Optional[str] = None
    notes: Optional[str] = None

class PatientWithFirstVisitCreate(BaseModel):
    full_name: str = Field(..., min_length=1, max_length=255)
    date_of_birth: date
    phone: Optional[str] = None
    allergies: Optional[str] = None
    chronic_conditions: Optional[str] = None
    medications: Optional[str] = None
    medical_history_notes: Optional[str] = None
    first_visit: FirstVisitCreate

class PatientUpdate(BaseModel):
    full_name: Optional[str] = Field(None, min_length=1, max_length=255)
    date_of_birth: Optional[date] = None
    phone: Optional[str] = None
    allergies: Optional[str] = None
    chronic_conditions: Optional[str] = None
    medications: Optional[str] = None
    medical_history_notes: Optional[str] = None

class VisitCreate(BaseModel):
    visit_date: date
    chief_complaint: Optional[str] = None
    history_of_present_illness: Optional[str] = None
    past_medical_history: Optional[str] = None
    blood_pressure_systolic: Optional[int] = None
    blood_pressure_diastolic: Optional[int] = None
    temperature: Optional[float] = None
    oxygen_saturation: Optional[int] = None
    pulse: Optional[int] = None
    local_examination: Optional[str] = None
    investigations: Optional[str] = None
    primary_diagnosis: Optional[str] = None
    secondary_diagnosis: Optional[str] = None
    medications_prescribed: Optional[str] = None
    treatment_plan: Optional[str] = None
    follow_up_instructions: Optional[str] = None
    notes: Optional[str] = None

class VisitUpdate(BaseModel):
    visit_date: Optional[date] = None
    chief_complaint: Optional[str] = None
    history_of_present_illness: Optional[str] = None
    past_medical_history: Optional[str] = None
    blood_pressure_systolic: Optional[int] = None
    blood_pressure_diastolic: Optional[int] = None
    temperature: Optional[float] = None
    oxygen_saturation: Optional[int] = None
    pulse: Optional[int] = None
    local_examination: Optional[str] = None
    investigations: Optional[str] = None
    primary_diagnosis: Optional[str] = None
    secondary_diagnosis: Optional[str] = None
    medications_prescribed: Optional[str] = None
    treatment_plan: Optional[str] = None
    follow_up_instructions: Optional[str] = None
    notes: Optional[str] = None

# ============== Auth ==============
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer(auto_error=False)

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return pwd_context.verify(plain_password, hashed_password)

def create_access_token(expires_delta: Optional[timedelta] = None) -> str:
    expire = datetime.utcnow() + (expires_delta or timedelta(days=ACCESS_TOKEN_EXPIRE_DAYS))
    return jwt.encode({"exp": expire, "sub": "doctor"}, SECRET_KEY, algorithm=ALGORITHM)

def verify_token(credentials: HTTPAuthorizationCredentials = Depends(security)) -> bool:
    # Allow local mode without enforcing a password/token
    if credentials is None:
        return True
    token = credentials.credentials
    if token in ("local", "dev", ""):
        return True
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        if payload.get("sub") != "doctor":
            raise HTTPException(status_code=401, detail="Invalid token")
        return True
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

# ============== FastAPI App ==============
app = FastAPI(title="Dr. Medhat Clinic")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============== Auth Routes ==============
@app.post("/api/auth/login", response_model=TokenResponse)
def login(request: LoginRequest):
    if request.password is None or request.password.strip() == "":
        return TokenResponse(access_token=create_access_token())
    if not verify_password(request.password, DOCTOR_PASSWORD_HASH):
        raise HTTPException(status_code=401, detail="Incorrect password")
    return TokenResponse(access_token=create_access_token())

@app.post("/api/auth/verify")
def verify(token: bool = Depends(verify_token)):
    return {"valid": True}

# ============== Patient Routes ==============
@app.get("/api/patients")
def list_patients(
    query: Optional[str] = Query(None),
    db: Session = Depends(get_db),
    _: bool = Depends(verify_token)
):
    base_query = db.query(Patient).filter(Patient.is_deleted == False)
    if query:
        search_term = f"%{query}%"
        patients = base_query.filter(
            or_(Patient.full_name.ilike(search_term), Patient.phone.ilike(search_term))
        ).order_by(Patient.full_name).all()
    else:
        patients = base_query.order_by(Patient.updated_at.desc()).all()
    return [serialize_patient(p) for p in patients]

@app.post("/api/patients/with-visit", status_code=201)
def create_patient_with_first_visit(
    data: PatientWithFirstVisitCreate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_token)
):
    patient = Patient(
        full_name=data.full_name,
        date_of_birth=data.date_of_birth,
        phone=data.phone,
        allergies=data.allergies,
        chronic_conditions=data.chronic_conditions,
        medications=data.medications,
        medical_history_notes=data.medical_history_notes,
    )
    db.add(patient)
    db.flush()
    
    visit_data = data.first_visit.model_dump()
    visit_data["patient_id"] = patient.id
    visit_data["is_first_visit"] = True
    db.add(Visit(**visit_data))
    db.commit()
    db.refresh(patient)
    return serialize_patient(patient)

@app.get("/api/patients/{patient_id}")
def get_patient(patient_id: int, db: Session = Depends(get_db), _: bool = Depends(verify_token)):
    patient = db.query(Patient).filter(Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    return serialize_patient(patient)

@app.put("/api/patients/{patient_id}")
def update_patient(
    patient_id: int,
    patient_update: PatientUpdate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_token)
):
    patient = db.query(Patient).filter(Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    for field, value in patient_update.model_dump(exclude_unset=True).items():
        setattr(patient, field, value)
    db.commit()
    db.refresh(patient)
    return serialize_patient(patient)

@app.delete("/api/patients/{patient_id}")
def delete_patient(patient_id: int, db: Session = Depends(get_db), _: bool = Depends(verify_token)):
    patient = db.query(Patient).filter(Patient.id == patient_id).first()
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    patient.is_deleted = True
    db.commit()
    return {"message": "Patient deleted"}

# ============== Visit Routes ==============
@app.get("/api/patients/{patient_id}/visits")
def list_visits(patient_id: int, db: Session = Depends(get_db), _: bool = Depends(verify_token)):
    return db.query(Visit).filter(Visit.patient_id == patient_id).order_by(Visit.visit_date.desc()).all()

@app.post("/api/patients/{patient_id}/visits", status_code=201)
def create_visit(
    patient_id: int,
    visit: VisitCreate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_token)
):
    if not db.query(Patient).filter(Patient.id == patient_id).first():
        raise HTTPException(status_code=404, detail="Patient not found")
    visit_data = visit.model_dump()
    visit_data["patient_id"] = patient_id
    visit_data["is_first_visit"] = False
    db_visit = Visit(**visit_data)
    db.add(db_visit)
    db.commit()
    db.refresh(db_visit)
    return db_visit

@app.get("/api/visits/{visit_id}")
def get_visit(visit_id: int, db: Session = Depends(get_db), _: bool = Depends(verify_token)):
    visit = db.query(Visit).filter(Visit.id == visit_id).first()
    if not visit:
        raise HTTPException(status_code=404, detail="Visit not found")
    return visit

@app.put("/api/visits/{visit_id}")
def update_visit(
    visit_id: int,
    visit_update: VisitUpdate,
    db: Session = Depends(get_db),
    _: bool = Depends(verify_token)
):
    visit = db.query(Visit).filter(Visit.id == visit_id).first()
    if not visit:
        raise HTTPException(status_code=404, detail="Visit not found")
    for field, value in visit_update.model_dump(exclude_unset=True).items():
        setattr(visit, field, value)
    db.commit()
    db.refresh(visit)
    return visit

@app.get("/api/exports/patients.csv")
def export_patients_csv(db: Session = Depends(get_db), _: bool = Depends(verify_token)):
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow([
        "Patient ID",
        "Full Name",
        "Date of Birth",
        "Phone",
        "Last Visit Date",
        "Allergies",
        "Chronic Conditions",
        "Medications",
        "Medical History Notes",
    ])
    patients = (
        db.query(Patient)
        .filter(Patient.is_deleted == False)  # noqa: E712
        .order_by(Patient.full_name.asc())
        .all()
    )
    for patient in patients:
        last_visit_date = patient.visits[0].visit_date if patient.visits else ""
        writer.writerow([
            patient.id,
            patient.full_name,
            patient.date_of_birth,
            patient.phone or "",
            last_visit_date,
            patient.allergies or "",
            patient.chronic_conditions or "",
            patient.medications or "",
            patient.medical_history_notes or "",
        ])
    csv_bytes = output.getvalue().encode("utf-8")
    return Response(
        content=csv_bytes,
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=patients.csv"},
    )

@app.get("/api/backup")
def download_backup(_: bool = Depends(verify_token)):
    if not DATABASE_PATH.exists():
        raise HTTPException(status_code=404, detail="Database not found")
    timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"clinic_backup_{timestamp}.db"
    return FileResponse(
        path=str(DATABASE_PATH),
        media_type="application/octet-stream",
        filename=filename,
    )

@app.post("/api/restore")
def restore_backup(file: UploadFile = File(...), _: bool = Depends(verify_token)):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")
    if not file.filename.lower().endswith(".db"):
        raise HTTPException(status_code=400, detail="Invalid file type")

    # Validate file header (SQLite format)
    header = file.file.read(16)
    file.file.seek(0)
    if not header.startswith(b"SQLite format 3"):
        raise HTTPException(status_code=400, detail="Invalid database file")

    DATA_DIR.mkdir(exist_ok=True)
    backup_dir = DATA_DIR / "backups"
    backup_dir.mkdir(exist_ok=True)

    # Backup current DB before restore
    if DATABASE_PATH.exists():
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        safety_backup = backup_dir / f"clinic_backup_before_restore_{timestamp}.db"
        shutil.copy2(DATABASE_PATH, safety_backup)

    # Write uploaded file to temp then replace
    temp_path = DATA_DIR / ".restore_tmp.db"
    with temp_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    os.replace(temp_path, DATABASE_PATH)
    engine.dispose()

    return {"status": "restored"}

@app.get("/api/health")
def health():
    return {"status": "healthy"}

# ============== Static Files & SPA ==============
if STATIC_DIR.exists():
    app.mount("/assets", StaticFiles(directory=STATIC_DIR / "assets"), name="assets")

    @app.get("/login")
    def serve_login():
        login_file = STATIC_DIR / "login.html"
        if login_file.exists():
            return FileResponse(login_file, headers={"Cache-Control": "no-store"})
        html = """
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Dr. Medhat Clinic - Login</title>
    <style>
      body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        background: linear-gradient(180deg, #cfe6ff 0%, #eaf5ff 60%, #ffffff 100%); color: #0f172a; }
      .wrap { min-height: 100vh; display: flex; align-items: center; justify-content: center; padding: 24px; }
      .card { width: min(560px, 92vw); background: #fff; border-radius: 26px; padding: 32px 32px 30px 32px;
        box-shadow: 0 24px 55px rgba(15, 23, 42, 0.16); text-align: center; }
      .logo img { max-width: 300px; }
      h1 { font-size: 26px; margin: 14px 0 6px 0; }
      p { margin: 0 0 20px 0; color: #64748b; font-size: 17px; }
      .btn { display: inline-flex; align-items: center; justify-content: center; width: 100%; height: 58px;
        border-radius: 18px; background: linear-gradient(135deg, #1f78ff 0%, #3ea1ff 100%); color: #fff;
        font-weight: 600; font-size: 18px; letter-spacing: 0.2px; text-decoration: none;
        box-shadow: 0 14px 30px rgba(31, 120, 255, 0.28); }
    </style>
  </head>
  <body>
    <div class="wrap">
      <div class="card">
        <div class="logo"><img src="/logo.png" alt="Dr. Medhat Clinic" /></div>
        <h1>Welcome</h1>
        <p>Click Enter to continue</p>
        <a class="btn" href="/">Enter</a>
      </div>
    </div>
  </body>
</html>
        """.strip()
        return Response(content=html, media_type="text/html", headers={"Cache-Control": "no-store"})
    
    @app.get("/{full_path:path}")
    async def serve_spa(full_path: str):
        file_path = STATIC_DIR / full_path
        if file_path.exists() and file_path.is_file():
            return FileResponse(file_path)
        return FileResponse(STATIC_DIR / "index.html")
