"""
SKILLR Platform - Complete Flask Backend
CERN (Collision-Evasive Regret Network) AI + Full REST API
MongoDB Atlas Integration
"""

import os
import time
import math
import random
import hashlib
import numpy as np
from datetime import datetime, timedelta
from collections import defaultdict

from flask import Flask, request, jsonify
from flask_cors import CORS
from flask_jwt_extended import (
    JWTManager, create_access_token, create_refresh_token,
    jwt_required, get_jwt_identity
)
from pymongo import MongoClient, GEOSPHERE, TEXT
from pymongo.errors import DuplicateKeyError
import bcrypt

app = Flask(__name__)
CORS(app, origins="*")

# ─── CONFIG ──────────────────────────────────────────────────────────────────
app.config["JWT_SECRET_KEY"] = "skillr_secret_key_2026_prod_xyz"
app.config["JWT_ACCESS_TOKEN_EXPIRES"] = timedelta(days=7)
app.config["JWT_REFRESH_TOKEN_EXPIRES"] = timedelta(days=30)

jwt = JWTManager(app)

MONGO_URI = "mongodb+srv://user:user@cluster0.alv9usq.mongodb.net/?appName=Cluster0"
client = MongoClient(MONGO_URI)
db = client["skillr"]

# Collections
users_col = db["users"]
providers_col = db["providers"]
gigs_col = db["gigs"]
bookings_col = db["bookings"]
reviews_col = db["reviews"]
messages_col = db["messages"]
conversations_col = db["conversations"]
intent_col = db["intent_events"]
categories_col = db["categories"]

# Indexes
try:
    users_col.create_index("email", unique=True)
    users_col.create_index("phone", unique=True, sparse=True)
    providers_col.create_index([("location", GEOSPHERE)])
    gigs_col.create_index([("title", TEXT), ("description", TEXT), ("tags", TEXT)])
    gigs_col.create_index([("location", GEOSPHERE)])
    gigs_col.create_index("provider_id")
    gigs_col.create_index("category")
    bookings_col.create_index("consumer_id")
    bookings_col.create_index("provider_id")
    messages_col.create_index("conversation_id")
    intent_col.create_index([("gig_id", 1), ("timestamp", -1)])
except Exception as e:
    print(f"Index warning: {e}")


# ─── CERN AI ENGINE ──────────────────────────────────────────────────────────

class CERNEngine:
    """
    Collision-Evasive Regret Network
    Pre-request congestion control via Ghost Competition modeling
    """
    DECAY_RATE = 0.3         # γ: exponential decay rate
    WINDOW_SEC = 120         # ΔT: sliding temporal window (seconds)
    PENALTY_WEIGHT = 0.4     # θ3: concurrency penalty weight
    TEMPERATURE = 1.2        # κ: Boltzmann exploration temperature
    RATING_WEIGHT = 0.6      # θ1
    DISTANCE_WEIGHT = 0.4    # θ2

    @staticmethod
    def get_chi(gig_id: str) -> float:
        """
        Compute Latent Concurrency Vector χ_p(t)
        Weighted sum of active view-time events in sliding window
        """
        now = time.time()
        cutoff = now - CERNEngine.WINDOW_SEC

        events = list(intent_col.find({
            "gig_id": gig_id,
            "timestamp": {"$gte": cutoff}
        }))

        chi = 0.0
        for ev in events:
            age = now - ev["timestamp"]
            omega = ev.get("intent_weight", 0.5)
            chi += omega * math.exp(-CERNEngine.DECAY_RATE * age)

        return chi

    @staticmethod
    def greedy_utility(rating: float, distance_km: float) -> float:
        """u_greedy(c,p) = θ1·R_p − θ2·Δd(c,p)"""
        r = CERNEngine.RATING_WEIGHT * (rating / 5.0)
        d = CERNEngine.DISTANCE_WEIGHT * min(distance_km / 50.0, 1.0)
        return r - d

    @staticmethod
    def cern_utility(gig_id: str, rating: float, distance_km: float) -> float:
        """U_c(p,t) = u_greedy(c,p) − θ3·log(1 + χ_p(t))"""
        u_greedy = CERNEngine.greedy_utility(rating, distance_km)
        chi = CERNEngine.get_chi(gig_id)
        penalty = CERNEngine.PENALTY_WEIGHT * math.log(1 + chi)
        return u_greedy - penalty

    @staticmethod
    def boltzmann_rank(gigs_with_scores: list) -> list:
        """
        Softmax (Boltzmann) allocation over CERN utilities
        P(p|c,t) = exp(U(p)/κ) / Σ exp(U(k)/κ)
        """
        if not gigs_with_scores:
            return []
        scores = np.array([g["cern_score"] for g in gigs_with_scores])
        exp_scores = np.exp(scores / CERNEngine.TEMPERATURE)
        probs = exp_scores / exp_scores.sum()

        for i, gig in enumerate(gigs_with_scores):
            gig["allocation_prob"] = float(probs[i])
            gig["chi_value"] = CERNEngine.get_chi(str(gig.get("_id", "")))

        return sorted(gigs_with_scores, key=lambda x: x["allocation_prob"], reverse=True)

    @staticmethod
    def record_intent(gig_id: str, user_id: str, view_duration: float):
        """Record user view-time as probabilistic intent signal"""
        omega = min(view_duration / 30.0, 1.0)  # normalize: 30s = full intent
        intent_col.insert_one({
            "gig_id": gig_id,
            "user_id": user_id,
            "timestamp": time.time(),
            "view_duration": view_duration,
            "intent_weight": omega
        })

    @staticmethod
    def haversine(lat1, lon1, lat2, lon2) -> float:
        """Haversine distance in km"""
        R = 6371
        phi1, phi2 = math.radians(lat1), math.radians(lat2)
        dphi = math.radians(lat2 - lat1)
        dlambda = math.radians(lon2 - lon1)
        a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
        return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))


cern = CERNEngine()


# ─── HELPERS ─────────────────────────────────────────────────────────────────

def serialize(doc):
    """Convert MongoDB document to JSON-serializable dict"""
    if doc is None:
        return None
    doc = dict(doc)
    if "_id" in doc:
        doc["id"] = str(doc.pop("_id"))
    for k, v in doc.items():
        if hasattr(v, 'isoformat'):
            doc[k] = v.isoformat()
        elif isinstance(v, list):
            doc[k] = [serialize(i) if isinstance(i, dict) else i for i in v]
    return doc

def serialize_list(docs):
    return [serialize(d) for d in docs]

def error(msg, code=400):
    return jsonify({"success": False, "error": msg}), code

def ok(data=None, msg="Success"):
    return jsonify({"success": True, "message": msg, "data": data})

def hash_pw(pw: str) -> str:
    return bcrypt.hashpw(pw.encode(), bcrypt.gensalt()).decode()

def check_pw(pw: str, hashed: str) -> bool:
    return bcrypt.checkpw(pw.encode(), hashed.encode())


# ─── SEED DATA ───────────────────────────────────────────────────────────────

CATEGORIES = [
    {"slug": "electrician", "name": "Electrician", "icon": "⚡", "color": "#F59E0B",
     "subcategories": ["Wiring", "Panel Upgrade", "Lighting", "EV Charging", "Generator"]},
    {"slug": "plumber", "name": "Plumber", "icon": "🔧", "color": "#3B82F6",
     "subcategories": ["Leak Repair", "Pipe Installation", "Drainage", "Water Heater", "Bathroom Fitting"]},
    {"slug": "cook", "name": "Cook / Chef", "icon": "👨‍🍳", "color": "#10B981",
     "subcategories": ["Home Cooking", "Party Catering", "Tiffin Service", "Baking", "Diet Meals"]},
    {"slug": "mechanic", "name": "Mechanic", "icon": "🔩", "color": "#EF4444",
     "subcategories": ["Car Repair", "Bike Service", "AC Service", "Welding", "Painting"]},
    {"slug": "cleaner", "name": "Cleaner", "icon": "🧹", "color": "#8B5CF6",
     "subcategories": ["Home Cleaning", "Office Cleaning", "Deep Clean", "Carpet Cleaning", "Pest Control"]},
    {"slug": "carpenter", "name": "Carpenter", "icon": "🪚", "color": "#D97706",
     "subcategories": ["Furniture Repair", "Custom Build", "Flooring", "Door/Window", "Interior"]},
    {"slug": "painter", "name": "Painter", "icon": "🎨", "color": "#EC4899",
     "subcategories": ["Interior", "Exterior", "Waterproofing", "Texture", "Commercial"]},
    {"slug": "tutor", "name": "Tutor", "icon": "📚", "color": "#06B6D4",
     "subcategories": ["Math", "Science", "English", "Coding", "Music", "Art"]},
    {"slug": "photographer", "name": "Photographer", "icon": "📸", "color": "#F97316",
     "subcategories": ["Wedding", "Portrait", "Event", "Product", "Real Estate"]},
    {"slug": "driver", "name": "Driver", "icon": "🚗", "color": "#14B8A6",
     "subcategories": ["Cab", "Delivery", "Outstation", "Corporate", "Airport"]},
    {"slug": "nurse", "name": "Nurse / Caretaker", "icon": "💊", "color": "#F43F5E",
     "subcategories": ["Elder Care", "Baby Care", "Post-Surgery", "Physiotherapy", "Mental Health"]},
    {"slug": "it_support", "name": "IT Support", "icon": "💻", "color": "#7C3AED",
     "subcategories": ["PC Repair", "Networking", "Software", "CCTV", "Web Design"]},
]

@app.route("/api/seed/categories", methods=["POST"])
def seed_categories():
    categories_col.delete_many({})
    categories_col.insert_many(CATEGORIES)
    return ok(msg="Categories seeded")


# ─── AUTH ROUTES ─────────────────────────────────────────────────────────────

@app.route("/api/auth/register", methods=["POST"])
def register():
    d = request.json or {}
    required = ["name", "email", "password", "role"]
    for f in required:
        if not d.get(f):
            return error(f"'{f}' is required")

    role = d["role"]
    if role not in ["consumer", "provider"]:
        return error("role must be 'consumer' or 'provider'")

    if users_col.find_one({"email": d["email"].lower()}):
        return error("Email already registered")

    user = {
        "name": d["name"].strip(),
        "email": d["email"].lower().strip(),
        "password": hash_pw(d["password"]),
        "role": role,
        "phone": d.get("phone", ""),
        "avatar": d.get("avatar", ""),
        "bio": d.get("bio", ""),
        "city": d.get("city", ""),
        "location": d.get("location", None),  # {type: "Point", coordinates: [lng, lat]}
        "verified": False,
        "rating": 0.0,
        "total_reviews": 0,
        "total_bookings": 0,
        "wallet_balance": 0.0,
        "is_active": True,
        "is_online": False,
        "joined_at": datetime.utcnow(),
        "last_seen": datetime.utcnow(),
        "skills": [],
        "languages": ["Hindi", "English"],
        "notifications_enabled": True,
        "profile_complete": False,
    }

    if role == "provider":
        user.update({
            "categories": d.get("categories", []),
            "experience_years": d.get("experience_years", 0),
            "hourly_rate": d.get("hourly_rate", 0),
            "portfolio": [],
            "certifications": [],
            "total_earnings": 0.0,
            "jobs_completed": 0,
            "response_time_min": 30,
        })

    result = users_col.insert_one(user)
    user_id = str(result.inserted_id)

    access = create_access_token(identity=user_id)
    refresh = create_refresh_token(identity=user_id)

    return ok({
        "access_token": access,
        "refresh_token": refresh,
        "user": {
            "id": user_id,
            "name": user["name"],
            "email": user["email"],
            "role": user["role"],
            "avatar": user["avatar"],
        }
    }, "Registered successfully"), 201


@app.route("/api/auth/login", methods=["POST"])
def login():
    d = request.json or {}
    if not d.get("email") or not d.get("password"):
        return error("Email and password required")

    user = users_col.find_one({"email": d["email"].lower()})
    if not user or not check_pw(d["password"], user["password"]):
        return error("Invalid credentials", 401)

    if not user.get("is_active", True):
        return error("Account suspended", 403)

    users_col.update_one({"_id": user["_id"]}, {"$set": {"last_seen": datetime.utcnow(), "is_online": True}})

    uid = str(user["_id"])
    return ok({
        "access_token": create_access_token(identity=uid),
        "refresh_token": create_refresh_token(identity=uid),
        "user": {
            "id": uid,
            "name": user["name"],
            "email": user["email"],
            "role": user["role"],
            "avatar": user.get("avatar", ""),
            "rating": user.get("rating", 0),
            "verified": user.get("verified", False),
        }
    })


@app.route("/api/auth/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh_token():
    uid = get_jwt_identity()
    return ok({"access_token": create_access_token(identity=uid)})


@app.route("/api/auth/logout", methods=["POST"])
@jwt_required()
def logout():
    uid = get_jwt_identity()
    from bson import ObjectId
    users_col.update_one({"_id": ObjectId(uid)}, {"$set": {"is_online": False, "last_seen": datetime.utcnow()}})
    return ok(msg="Logged out")


# ─── USER / PROFILE ROUTES ───────────────────────────────────────────────────

@app.route("/api/user/me", methods=["GET"])
@jwt_required()
def get_me():
    from bson import ObjectId
    uid = get_jwt_identity()
    user = users_col.find_one({"_id": ObjectId(uid)})
    if not user:
        return error("User not found", 404)
    user.pop("password", None)
    return ok(serialize(user))


@app.route("/api/user/me", methods=["PUT"])
@jwt_required()
def update_me():
    from bson import ObjectId
    uid = get_jwt_identity()
    d = request.json or {}
    allowed = [
        "name", "phone", "bio", "city", "location", "avatar",
        "skills", "languages", "categories", "experience_years",
        "hourly_rate", "certifications", "notifications_enabled",
        "response_time_min"
    ]
    updates = {k: d[k] for k in allowed if k in d}
    updates["last_seen"] = datetime.utcnow()

    # Check profile completeness
    user = users_col.find_one({"_id": ObjectId(uid)})
    if user:
        merged = {**user, **updates}
        complete = bool(merged.get("name") and merged.get("phone") and
                       merged.get("bio") and merged.get("city") and merged.get("avatar"))
        updates["profile_complete"] = complete

    users_col.update_one({"_id": ObjectId(uid)}, {"$set": updates})
    return ok(msg="Profile updated")


@app.route("/api/user/<user_id>", methods=["GET"])
def get_user_public(user_id):
    from bson import ObjectId
    try:
        user = users_col.find_one({"_id": ObjectId(user_id)})
    except:
        return error("Invalid ID", 404)
    if not user:
        return error("User not found", 404)
    user.pop("password", None)
    user.pop("email", None)
    return ok(serialize(user))


@app.route("/api/user/me/portfolio", methods=["POST"])
@jwt_required()
def add_portfolio():
    from bson import ObjectId
    uid = get_jwt_identity()
    d = request.json or {}
    item = {
        "id": str(ObjectId()),
        "title": d.get("title", ""),
        "description": d.get("description", ""),
        "image_url": d.get("image_url", ""),
        "category": d.get("category", ""),
        "added_at": datetime.utcnow().isoformat()
    }
    users_col.update_one({"_id": ObjectId(uid)}, {"$push": {"portfolio": item}})
    return ok(item, "Portfolio item added")


@app.route("/api/user/online", methods=["POST"])
@jwt_required()
def set_online():
    from bson import ObjectId
    uid = get_jwt_identity()
    d = request.json or {}
    users_col.update_one({"_id": ObjectId(uid)}, {
        "$set": {"is_online": d.get("online", True), "last_seen": datetime.utcnow()}
    })
    return ok()


# ─── CATEGORIES ──────────────────────────────────────────────────────────────

@app.route("/api/categories", methods=["GET"])
def get_categories():
    cats = list(categories_col.find())
    if not cats:
        categories_col.insert_many(CATEGORIES)
        cats = list(categories_col.find())
    return ok(serialize_list(cats))


# ─── GIGS ROUTES ─────────────────────────────────────────────────────────────

@app.route("/api/gigs", methods=["POST"])
@jwt_required()
def create_gig():
    from bson import ObjectId
    uid = get_jwt_identity()
    user = users_col.find_one({"_id": ObjectId(uid)})
    if not user or user.get("role") != "provider":
        return error("Only providers can create gigs", 403)

    d = request.json or {}
    required = ["title", "category", "description", "pricing"]
    for f in required:
        if not d.get(f):
            return error(f"'{f}' is required")

    gig = {
        "provider_id": uid,
        "provider_name": user["name"],
        "provider_avatar": user.get("avatar", ""),
        "provider_rating": user.get("rating", 0),
        "provider_jobs": user.get("jobs_completed", 0),
        "title": d["title"].strip(),
        "category": d["category"],
        "subcategory": d.get("subcategory", ""),
        "description": d["description"].strip(),
        "tags": d.get("tags", []),
        "images": d.get("images", []),
        "pricing": d["pricing"],  # [{tier: "basic", price: 500, desc: "...", duration_hours: 2}]
        "location": d.get("location"),  # {type: "Point", coordinates: [lng, lat]}
        "city": d.get("city", user.get("city", "")),
        "service_radius_km": d.get("service_radius_km", 10),
        "availability": d.get("availability", {
            "days": ["Mon","Tue","Wed","Thu","Fri"],
            "start_time": "08:00",
            "end_time": "20:00"
        }),
        "is_active": True,
        "is_featured": False,
        "rating": 0.0,
        "total_reviews": 0,
        "total_bookings": 0,
        "views": 0,
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
    }

    result = gigs_col.insert_one(gig)
    return ok({"gig_id": str(result.inserted_id)}, "Gig created"), 201


@app.route("/api/gigs", methods=["GET"])
def list_gigs():
    """
    CERN-powered gig listing with:
    - Geo-proximity filtering
    - Ghost Competition penalty
    - Boltzmann probabilistic ranking
    """
    category = request.args.get("category", "")
    search = request.args.get("q", "")
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    radius_km = request.args.get("radius", 20, type=float)
    min_price = request.args.get("min_price", type=float)
    max_price = request.args.get("max_price", type=float)
    min_rating = request.args.get("min_rating", 0, type=float)
    sort_by = request.args.get("sort", "cern")  # cern | rating | price | newest
    page = request.args.get("page", 1, type=int)
    limit = request.args.get("limit", 20, type=int)
    user_id = request.args.get("user_id", "")

    query = {"is_active": True}

    if category:
        query["category"] = category

    if search:
        query["$text"] = {"$search": search}

    if min_rating > 0:
        query["rating"] = {"$gte": min_rating}

    # Geo query
    if lat and lng:
        query["location"] = {
            "$near": {
                "$geometry": {"type": "Point", "coordinates": [lng, lat]},
                "$maxDistance": radius_km * 1000
            }
        }

    # Price filter (check min pricing tier)
    if min_price or max_price:
        price_q = {}
        if min_price:
            price_q["$gte"] = min_price
        if max_price:
            price_q["$lte"] = max_price
        query["pricing.0.price"] = price_q

    try:
        raw_gigs = list(gigs_col.find(query).skip((page-1)*limit).limit(limit))
    except Exception as e:
        # Fallback without geo if index not ready
        query.pop("location", None)
        raw_gigs = list(gigs_col.find(query).skip((page-1)*limit).limit(limit))

    # Apply CERN scoring
    for gig in raw_gigs:
        gid = str(gig["_id"])
        rating = gig.get("rating", 0) or 0
        distance_km = 0
        if lat and lng and gig.get("location"):
            coords = gig["location"]["coordinates"]
            distance_km = cern.haversine(lat, lng, coords[1], coords[0])

        if sort_by == "cern":
            gig["cern_score"] = cern.cern_utility(gid, rating, distance_km)
        else:
            gig["cern_score"] = cern.greedy_utility(rating, distance_km)

        gig["distance_km"] = round(distance_km, 2)

    if sort_by == "cern" and len(raw_gigs) > 1:
        ranked = cern.boltzmann_rank(raw_gigs)
    elif sort_by == "rating":
        ranked = sorted(raw_gigs, key=lambda x: x.get("rating", 0), reverse=True)
    elif sort_by == "price":
        ranked = sorted(raw_gigs, key=lambda x: x.get("pricing", [{}])[0].get("price", 0))
    elif sort_by == "newest":
        ranked = sorted(raw_gigs, key=lambda x: x.get("created_at", datetime.min), reverse=True)
    else:
        ranked = raw_gigs

    # Record intent if user provided
    if user_id:
        for gig in ranked[:5]:  # top 5 shown = intent signal
            cern.record_intent(str(gig["_id"]), user_id, 2.0)

    total = gigs_col.count_documents({k: v for k, v in query.items() if k != "location"})

    return ok({
        "gigs": serialize_list(ranked),
        "total": total,
        "page": page,
        "pages": math.ceil(total / limit),
        "cern_active": sort_by == "cern"
    })


@app.route("/api/gigs/<gig_id>", methods=["GET"])
def get_gig(gig_id):
    from bson import ObjectId
    try:
        gig = gigs_col.find_one({"_id": ObjectId(gig_id)})
    except:
        return error("Invalid gig ID", 404)
    if not gig:
        return error("Gig not found", 404)

    # Increment views
    gigs_col.update_one({"_id": ObjectId(gig_id)}, {"$inc": {"views": 1}})

    # Get provider info
    provider = users_col.find_one({"_id": ObjectId(gig["provider_id"])})
    if provider:
        provider.pop("password", None)
        provider.pop("email", None)
        gig["provider"] = serialize(provider)

    # Get recent reviews
    reviews = list(reviews_col.find({"gig_id": gig_id}).sort("created_at", -1).limit(10))
    gig["reviews"] = serialize_list(reviews)

    # CERN: chi value
    gig["chi_value"] = cern.get_chi(gig_id)
    gig["ghost_competition_level"] = (
        "Low" if gig["chi_value"] < 1 else
        "Medium" if gig["chi_value"] < 3 else "High"
    )

    return ok(serialize(gig))


@app.route("/api/gigs/<gig_id>", methods=["PUT"])
@jwt_required()
def update_gig(gig_id):
    from bson import ObjectId
    uid = get_jwt_identity()
    gig = gigs_col.find_one({"_id": ObjectId(gig_id)})
    if not gig or gig["provider_id"] != uid:
        return error("Unauthorized", 403)

    d = request.json or {}
    allowed = ["title","description","pricing","images","tags","availability",
               "service_radius_km","is_active","city","location","subcategory"]
    updates = {k: d[k] for k in allowed if k in d}
    updates["updated_at"] = datetime.utcnow()
    gigs_col.update_one({"_id": ObjectId(gig_id)}, {"$set": updates})
    return ok(msg="Gig updated")


@app.route("/api/gigs/<gig_id>", methods=["DELETE"])
@jwt_required()
def delete_gig(gig_id):
    from bson import ObjectId
    uid = get_jwt_identity()
    gig = gigs_col.find_one({"_id": ObjectId(gig_id)})
    if not gig or gig["provider_id"] != uid:
        return error("Unauthorized", 403)
    gigs_col.delete_one({"_id": ObjectId(gig_id)})
    return ok(msg="Gig deleted")


@app.route("/api/gigs/my/list", methods=["GET"])
@jwt_required()
def my_gigs():
    uid = get_jwt_identity()
    gigs = list(gigs_col.find({"provider_id": uid}).sort("created_at", -1))
    return ok(serialize_list(gigs))


# ─── INTENT / CERN TELEMETRY ─────────────────────────────────────────────────

@app.route("/api/intent/view", methods=["POST"])
@jwt_required()
def record_view():
    uid = get_jwt_identity()
    d = request.json or {}
    if not d.get("gig_id"):
        return error("gig_id required")
    cern.record_intent(d["gig_id"], uid, d.get("duration_seconds", 5.0))
    return ok({"chi": cern.get_chi(d["gig_id"])})


@app.route("/api/intent/chi/<gig_id>", methods=["GET"])
def get_chi(gig_id):
    chi = cern.get_chi(gig_id)
    level = "Low" if chi < 1 else "Medium" if chi < 3 else "High"
    return ok({"chi": chi, "level": level, "competition": round(chi * 10, 1)})


@app.route("/api/cern/stats", methods=["GET"])
def cern_stats():
    """Dashboard stats for CERN collision metrics"""
    total_intents = intent_col.count_documents({})
    now = time.time()
    active_intents = intent_col.count_documents({"timestamp": {"$gte": now - 120}})

    # Top contested gigs
    pipeline = [
        {"$match": {"timestamp": {"$gte": now - 120}}},
        {"$group": {"_id": "$gig_id", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}},
        {"$limit": 5}
    ]
    hot_gigs = list(intent_col.aggregate(pipeline))

    return ok({
        "total_intent_events": total_intents,
        "active_intent_window": active_intents,
        "hot_gigs": hot_gigs,
        "cern_params": {
            "decay_rate": cern.DECAY_RATE,
            "window_sec": cern.WINDOW_SEC,
            "penalty_weight": cern.PENALTY_WEIGHT,
            "temperature": cern.TEMPERATURE
        }
    })


# ─── BOOKINGS ROUTES ─────────────────────────────────────────────────────────

@app.route("/api/bookings", methods=["POST"])
@jwt_required()
def create_booking():
    from bson import ObjectId
    uid = get_jwt_identity()
    user = users_col.find_one({"_id": ObjectId(uid)})
    if not user:
        return error("User not found", 404)

    d = request.json or {}
    if not d.get("gig_id"):
        return error("gig_id required")

    gig = gigs_col.find_one({"_id": ObjectId(d["gig_id"])})
    if not gig:
        return error("Gig not found", 404)

    if gig["provider_id"] == uid:
        return error("Cannot book your own gig", 400)

    pricing_tier = d.get("pricing_tier", 0)
    pricing = gig["pricing"][pricing_tier] if gig["pricing"] else {}

    booking = {
        "consumer_id": uid,
        "consumer_name": user["name"],
        "consumer_avatar": user.get("avatar", ""),
        "provider_id": gig["provider_id"],
        "provider_name": gig["provider_name"],
        "gig_id": d["gig_id"],
        "gig_title": gig["title"],
        "gig_category": gig["category"],
        "pricing_tier": pricing,
        "scheduled_date": d.get("scheduled_date"),
        "scheduled_time": d.get("scheduled_time"),
        "address": d.get("address", ""),
        "location": d.get("location"),
        "notes": d.get("notes", ""),
        "status": "pending",  # pending | accepted | in_progress | completed | cancelled | disputed
        "amount": pricing.get("price", 0),
        "payment_status": "pending",  # pending | paid | refunded
        "payment_method": d.get("payment_method", "cod"),
        "created_at": datetime.utcnow(),
        "updated_at": datetime.utcnow(),
        "completed_at": None,
        "cancelled_at": None,
        "cancel_reason": "",
    }

    result = bookings_col.insert_one(booking)
    bid = str(result.inserted_id)

    # Update stats
    gigs_col.update_one({"_id": ObjectId(d["gig_id"])}, {"$inc": {"total_bookings": 1}})
    users_col.update_one({"_id": ObjectId(uid)}, {"$inc": {"total_bookings": 1}})

    # Create conversation
    conv_id = f"{uid}_{gig['provider_id']}_{d['gig_id']}"
    conversations_col.update_one(
        {"conv_id": conv_id},
        {"$setOnInsert": {
            "conv_id": conv_id,
            "participants": [uid, gig["provider_id"]],
            "gig_id": d["gig_id"],
            "booking_id": bid,
            "last_message": "Booking request sent",
            "last_message_at": datetime.utcnow(),
            "unread": {uid: 0, gig["provider_id"]: 1}
        }},
        upsert=True
    )

    return ok({"booking_id": bid}, "Booking created"), 201


@app.route("/api/bookings", methods=["GET"])
@jwt_required()
def list_bookings():
    uid = get_jwt_identity()
    role = request.args.get("role", "consumer")  # consumer | provider
    status = request.args.get("status")

    query = {}
    if role == "consumer":
        query["consumer_id"] = uid
    else:
        query["provider_id"] = uid

    if status:
        query["status"] = status

    bookings = list(bookings_col.find(query).sort("created_at", -1).limit(50))
    return ok(serialize_list(bookings))


@app.route("/api/bookings/<booking_id>", methods=["GET"])
@jwt_required()
def get_booking(booking_id):
    from bson import ObjectId
    uid = get_jwt_identity()
    try:
        booking = bookings_col.find_one({"_id": ObjectId(booking_id)})
    except:
        return error("Invalid ID", 404)
    if not booking:
        return error("Not found", 404)
    if booking["consumer_id"] != uid and booking["provider_id"] != uid:
        return error("Unauthorized", 403)
    return ok(serialize(booking))


@app.route("/api/bookings/<booking_id>/status", methods=["PUT"])
@jwt_required()
def update_booking_status(booking_id):
    from bson import ObjectId
    uid = get_jwt_identity()
    d = request.json or {}
    new_status = d.get("status")
    valid_statuses = ["accepted", "rejected", "in_progress", "completed", "cancelled"]
    if new_status not in valid_statuses:
        return error(f"Invalid status. Choose: {valid_statuses}")

    try:
        booking = bookings_col.find_one({"_id": ObjectId(booking_id)})
    except:
        return error("Invalid ID")
    if not booking:
        return error("Booking not found", 404)

    is_provider = booking["provider_id"] == uid
    is_consumer = booking["consumer_id"] == uid

    provider_actions = ["accepted", "rejected", "in_progress", "completed"]
    consumer_actions = ["cancelled"]

    if new_status in provider_actions and not is_provider:
        return error("Only provider can perform this action", 403)
    if new_status in consumer_actions and not is_consumer:
        return error("Only consumer can perform this action", 403)

    updates = {"status": new_status, "updated_at": datetime.utcnow()}
    if new_status == "completed":
        updates["completed_at"] = datetime.utcnow()
        users_col.update_one(
            {"_id": ObjectId(booking["provider_id"])},
            {"$inc": {"jobs_completed": 1, "total_earnings": booking.get("amount", 0)}}
        )
    if new_status == "cancelled":
        updates["cancelled_at"] = datetime.utcnow()
        updates["cancel_reason"] = d.get("reason", "")

    bookings_col.update_one({"_id": ObjectId(booking_id)}, {"$set": updates})
    return ok(msg=f"Booking {new_status}")


# ─── REVIEWS ─────────────────────────────────────────────────────────────────

@app.route("/api/reviews", methods=["POST"])
@jwt_required()
def create_review():
    from bson import ObjectId
    uid = get_jwt_identity()
    d = request.json or {}

    if not all([d.get("gig_id"), d.get("booking_id"), d.get("rating")]):
        return error("gig_id, booking_id, rating required")

    # Verify booking
    booking = bookings_col.find_one({"_id": ObjectId(d["booking_id"])})
    if not booking or booking["consumer_id"] != uid:
        return error("Unauthorized", 403)
    if booking["status"] != "completed":
        return error("Can only review completed bookings")

    if reviews_col.find_one({"booking_id": d["booking_id"], "reviewer_id": uid}):
        return error("Already reviewed this booking")

    user = users_col.find_one({"_id": ObjectId(uid)})
    rating = max(1, min(5, int(d["rating"])))

    review = {
        "gig_id": d["gig_id"],
        "booking_id": d["booking_id"],
        "reviewer_id": uid,
        "reviewer_name": user["name"],
        "reviewer_avatar": user.get("avatar", ""),
        "provider_id": booking["provider_id"],
        "rating": rating,
        "comment": d.get("comment", "").strip(),
        "tags": d.get("tags", []),  # ["Professional", "On Time", "Quality Work"]
        "created_at": datetime.utcnow(),
    }

    reviews_col.insert_one(review)

    # Update gig rating
    all_reviews = list(reviews_col.find({"gig_id": d["gig_id"]}))
    avg_rating = sum(r["rating"] for r in all_reviews) / len(all_reviews)
    gigs_col.update_one(
        {"_id": ObjectId(d["gig_id"])},
        {"$set": {"rating": round(avg_rating, 2), "total_reviews": len(all_reviews)}}
    )

    # Update provider rating
    all_provider_reviews = list(reviews_col.find({"provider_id": booking["provider_id"]}))
    prov_avg = sum(r["rating"] for r in all_provider_reviews) / len(all_provider_reviews)
    users_col.update_one(
        {"_id": ObjectId(booking["provider_id"])},
        {"$set": {"rating": round(prov_avg, 2), "total_reviews": len(all_provider_reviews)}}
    )

    return ok(msg="Review submitted"), 201


@app.route("/api/reviews/<gig_id>", methods=["GET"])
def get_reviews(gig_id):
    reviews = list(reviews_col.find({"gig_id": gig_id}).sort("created_at", -1).limit(20))
    total = reviews_col.count_documents({"gig_id": gig_id})
    avg = sum(r["rating"] for r in reviews) / len(reviews) if reviews else 0
    return ok({"reviews": serialize_list(reviews), "total": total, "average": round(avg, 2)})


# ─── MESSAGING ROUTES ────────────────────────────────────────────────────────

@app.route("/api/conversations", methods=["GET"])
@jwt_required()
def list_conversations():
    uid = get_jwt_identity()
    convs = list(conversations_col.find({"participants": uid}).sort("last_message_at", -1))
    return ok(serialize_list(convs))


@app.route("/api/messages/<conv_id>", methods=["GET"])
@jwt_required()
def get_messages(conv_id):
    uid = get_jwt_identity()
    conv = conversations_col.find_one({"conv_id": conv_id})
    if not conv or uid not in conv["participants"]:
        return error("Unauthorized", 403)

    msgs = list(messages_col.find({"conv_id": conv_id}).sort("sent_at", 1).limit(100))

    # Mark as read
    conversations_col.update_one(
        {"conv_id": conv_id},
        {"$set": {f"unread.{uid}": 0}}
    )

    return ok(serialize_list(msgs))


@app.route("/api/messages", methods=["POST"])
@jwt_required()
def send_message():
    uid = get_jwt_identity()
    d = request.json or {}
    if not d.get("conv_id") or not d.get("text"):
        return error("conv_id and text required")

    conv = conversations_col.find_one({"conv_id": d["conv_id"]})
    if not conv or uid not in conv["participants"]:
        return error("Unauthorized", 403)

    from bson import ObjectId
    user = users_col.find_one({"_id": ObjectId(uid)})
    other_id = [p for p in conv["participants"] if p != uid][0]

    msg = {
        "conv_id": d["conv_id"],
        "sender_id": uid,
        "sender_name": user["name"],
        "sender_avatar": user.get("avatar", ""),
        "text": d["text"].strip(),
        "type": d.get("type", "text"),  # text | image | booking | location
        "attachment": d.get("attachment"),
        "sent_at": datetime.utcnow(),
        "read": False,
    }

    messages_col.insert_one(msg)
    conversations_col.update_one(
        {"conv_id": d["conv_id"]},
        {"$set": {
            "last_message": d["text"][:50],
            "last_message_at": datetime.utcnow(),
        },
         "$inc": {f"unread.{other_id}": 1}}
    )

    return ok(serialize(msg), "Message sent"), 201


# ─── SEARCH & DISCOVERY ──────────────────────────────────────────────────────

@app.route("/api/search", methods=["GET"])
def search():
    q = request.args.get("q", "")
    if len(q) < 2:
        return ok({"gigs": [], "providers": []})

    # Text search gigs
    gigs = list(gigs_col.find({
        "$text": {"$search": q},
        "is_active": True
    }, {"score": {"$meta": "textScore"}}).sort([("score", {"$meta": "textScore"})]).limit(10))

    # Search providers
    providers = list(users_col.find({
        "role": "provider",
        "is_active": True,
        "$or": [
            {"name": {"$regex": q, "$options": "i"}},
            {"bio": {"$regex": q, "$options": "i"}},
            {"skills": {"$regex": q, "$options": "i"}},
            {"categories": {"$regex": q, "$options": "i"}},
        ]
    }).limit(5))

    for p in providers:
        p.pop("password", None)
        p.pop("email", None)

    return ok({"gigs": serialize_list(gigs), "providers": serialize_list(providers)})


@app.route("/api/gigs/nearby", methods=["GET"])
def nearby_gigs():
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    radius_km = request.args.get("radius", 5, type=float)
    category = request.args.get("category")

    if not lat or not lng:
        return error("lat and lng required")

    query = {
        "is_active": True,
        "location": {
            "$near": {
                "$geometry": {"type": "Point", "coordinates": [lng, lat]},
                "$maxDistance": radius_km * 1000
            }
        }
    }
    if category:
        query["category"] = category

    try:
        gigs = list(gigs_col.find(query).limit(20))
    except:
        gigs = list(gigs_col.find({"is_active": True, "category": category} if category else {"is_active": True}).limit(20))

    for gig in gigs:
        if gig.get("location"):
            coords = gig["location"]["coordinates"]
            gig["distance_km"] = round(cern.haversine(lat, lng, coords[1], coords[0]), 2)
        gig["chi_value"] = cern.get_chi(str(gig["_id"]))

    return ok(serialize_list(gigs))


# ─── DASHBOARD / ANALYTICS ───────────────────────────────────────────────────

@app.route("/api/dashboard/consumer", methods=["GET"])
@jwt_required()
def consumer_dashboard():
    uid = get_jwt_identity()
    total_bookings = bookings_col.count_documents({"consumer_id": uid})
    active = bookings_col.count_documents({"consumer_id": uid, "status": {"$in": ["pending","accepted","in_progress"]}})
    completed = bookings_col.count_documents({"consumer_id": uid, "status": "completed"})
    recent = list(bookings_col.find({"consumer_id": uid}).sort("created_at", -1).limit(5))
    return ok({
        "total_bookings": total_bookings,
        "active_bookings": active,
        "completed_bookings": completed,
        "recent_bookings": serialize_list(recent)
    })


@app.route("/api/dashboard/provider", methods=["GET"])
@jwt_required()
def provider_dashboard():
    from bson import ObjectId
    uid = get_jwt_identity()
    user = users_col.find_one({"_id": ObjectId(uid)})

    total_gigs = gigs_col.count_documents({"provider_id": uid})
    total_bookings = bookings_col.count_documents({"provider_id": uid})
    pending = bookings_col.count_documents({"provider_id": uid, "status": "pending"})
    completed = bookings_col.count_documents({"provider_id": uid, "status": "completed"})
    total_views = sum(g.get("views", 0) for g in gigs_col.find({"provider_id": uid}))

    recent = list(bookings_col.find({"provider_id": uid}).sort("created_at", -1).limit(5))

    return ok({
        "total_gigs": total_gigs,
        "total_bookings": total_bookings,
        "pending_bookings": pending,
        "completed_bookings": completed,
        "total_views": total_views,
        "total_earnings": user.get("total_earnings", 0),
        "rating": user.get("rating", 0),
        "recent_bookings": serialize_list(recent)
    })


# ─── HEALTH CHECK ─────────────────────────────────────────────────────────────

@app.route("/api/health", methods=["GET"])
def health():
    try:
        db.command("ping")
        db_status = "connected"
    except:
        db_status = "disconnected"
    return ok({
        "status": "running",
        "db": db_status,
        "version": "1.0.0",
        "cern": "active"
    })


# ─── FEATURED / TRENDING ─────────────────────────────────────────────────────

@app.route("/api/gigs/featured", methods=["GET"])
def featured_gigs():
    gigs = list(gigs_col.find({"is_active": True, "rating": {"$gte": 4}})
                .sort("total_bookings", -1).limit(8))
    return ok(serialize_list(gigs))


@app.route("/api/gigs/trending", methods=["GET"])
def trending_gigs():
    """Trending = most viewed + high chi (active interest)"""
    gigs = list(gigs_col.find({"is_active": True}).sort("views", -1).limit(12))
    for gig in gigs:
        gig["chi_value"] = cern.get_chi(str(gig["_id"]))
    gigs.sort(key=lambda x: x.get("views", 0) + x.get("chi_value", 0) * 10, reverse=True)
    return ok(serialize_list(gigs))


if __name__ == "__main__":
    # Seed categories on start
    if categories_col.count_documents({}) == 0:
        categories_col.insert_many(CATEGORIES)
        print("✅ Categories seeded")

    print("🚀 SKILLR Backend starting on port 5000")
    print("🧠 CERN AI Engine: ACTIVE")
    app.run(debug=True, port=5000, host="0.0.0.0")