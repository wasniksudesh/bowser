import os
import sys
import json
import requests

# Constants
BASE_URL = "https://api.content.tripadvisor.com/api/v1"
API_KEY = os.getenv("TRIPADVISOR_API_KEY")

def fetch_data(url, params=None):
    """Generic function to fetch data from TripAdvisor API."""
    if params is None:
        params = {}
    params['key'] = API_KEY
    
    headers = {"accept": "application/json"}
    try:
        response = requests.get(url, params=params, headers=headers)
        response.raise_for_status()
        return response.json()
    except requests.RequestException as e:
        print(f"Error fetching data from {url}: {e}", file=sys.stderr)
        return None

def search_hotels(query, limit=5):
    """Search for hotels matching the query."""
    url = f"{BASE_URL}/location/search"
    params = {
        "searchQuery": query,
        "category": "hotels",
        "language": "en"
    }
    data = fetch_data(url, params)
    if data and "data" in data:
        return data["data"][:limit]
    return []

def get_location_details(location_id):
    """Get specific details for a location."""
    url = f"{BASE_URL}/location/{location_id}/details"
    data = fetch_data(url, {"language": "en", "currency": "USD"})
    
    if not data:
        return None
        
    # Get only required fields
    amenities_list = data.get("amenities", [])
    amenities_str = ", ".join(amenities_list) if isinstance(amenities_list, list) else ""
    
    return {
        "rating": data.get("rating"),
        "web_url": data.get("web_url"),
        "location_id": data.get("location_id"),
        "description": data.get("description"),
        "name": data.get("name"),
        "review_rating_count": data.get("review_rating_count"),
        "see_all_photos": data.get("see_all_photos"),
        "amenities": amenities_str
    }

def get_location_photos(location_id):
    """Get photos for a specific location and return the first original photo URL."""
    url = f"{BASE_URL}/location/{location_id}/photos"
    data = fetch_data(url, {"language": "en", "limit": 5, "offset": 0})
    if data and "data" in data and len(data["data"]) > 0:
        first_photo = data["data"][0]
        return first_photo.get("images", {}).get("original", {}).get("url")
    return None

def get_location_reviews(location_id):
    """Get reviews and return a consolidated string."""
    url = f"{BASE_URL}/location/{location_id}/reviews"
    data = fetch_data(url, {"language": "en", "limit": 5, "offset": 0})
    if data and "data" in data:
        reviews = data["data"]
        consolidated = "\n---\n".join([f"{r.get('title', 'Review')}: {r.get('text', '')}" for r in reviews])
        return consolidated
    return ""

def main():
    if not API_KEY:
        print("Error: TRIPADVISOR_API_KEY environment variable not set.")
        sys.exit(1)

    if len(sys.argv) > 1:
        query = " ".join(sys.argv[1:])
    else:
        query = input("Enter search term (e.g. 'Manali hotels'): ")

    if not query:
        print("Error: No search term provided.")
        sys.exit(1)

    print(f"Searching for hotels in '{query}'...", file=sys.stderr)
    hotels = search_hotels(query)

    if not hotels:
        print("No hotels found.")
        return

    results = []
    for hotel in hotels:
        loc_id = hotel["location_id"]
        print(f"Fetching details for {hotel['name']} (ID: {loc_id})...", file=sys.stderr)
        
        details = get_location_details(loc_id)
        photo_url = get_location_photos(loc_id)
        consolidated_review = get_location_reviews(loc_id)
        
        result_entry = {
            "name": hotel.get("name"),
            "location_id": loc_id,
            "details": details,
            "original-photo": photo_url,
            "consolidated-review": consolidated_review,
            "rating": details.get("rating") if details else None
        }
        results.append(result_entry)

    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
