import json

collection = {
  "info": {
    "name": "Primhub - Full API",
    "description": "Colección completa de todas las llamadas a la API generadas desde el código fuente de Flutter.",
    "schema": "https://schema.getpostman.com/json/collection/v2.1.0/collection.json"
  },
  "auth": {
    "type": "bearer",
    "bearer": [
      {
        "key": "token",
        "value": "{{tokenPrimhub}}",
        "type": "string"
      }
    ]
  },
  "variable": [
    { "key": "BaseURL", "value": "https://primhub.primware.net" },
    { "key": "tokenPrimhub", "value": "" }
  ],
  "item": []
}

def add_request(name, method, path, query=None, body=None):
    req = {
        "name": name,
        "request": {
            "method": method,
            "header": [
                {"key": "Content-Type", "value": "application/json"}
            ],
            "url": {
                "raw": f"{{{{BaseURL}}}}/{path}" + ("" if not query else "?" + "&".join([f"{k}={v}" for k,v in query.items()])),
                "host": ["{{BaseURL}}"],
                "path": path.split("/")
            }
        }
    }
    if query:
        req["request"]["url"]["query"] = [{"key": k, "value": v} for k, v in query.items()]
    if body:
        req["request"]["body"] = {
            "mode": "raw",
            "raw": json.dumps(body, indent=2),
            "options": {"raw": {"language": "json"}}
        }
    collection["item"].append(req)

# Auth
add_request("Autenticación (Login)", "POST", "api/v1/auth/tokens", body={"userName": "tu_usuario", "password": "tu_password"})

# Modelos GET
add_request("Obtener Solicitudes", "GET", "api/v1/models/R_Request", query={
    "$filter": "C_BPartner_ID eq 1000013 and Created ge '2026-01-01T00:00:00Z' and Created le '2026-12-31T23:59:59Z'",
    "$expand": "C_Order_ID($select=DocumentNo),R_Status_ID($select=Name,IsOpen,IsClosed),R_RequestType_ID,R_Category_ID,C_BPartner_ID($select=Name,Description)",
    "$orderby": "Updated desc",
    "$top": "50"
})

add_request("Obtener Actualizaciones", "GET", "api/v1/models/R_RequestUpdate", query={
    "$filter": "R_Request_ID eq 1000000",
    "$expand": "CreatedBy($select=Name),ConfidentialTypeEntry"
})

add_request("Obtener Usuarios (AD_User)", "GET", "api/v1/models/AD_User", query={"$filter": "IsActive eq true"})
add_request("Obtener Terceros (C_BPartner)", "GET", "api/v1/models/C_BPartner", query={"$filter": "IsActive eq true"})
add_request("Obtener Estados (R_Status)", "GET", "api/v1/models/R_Status", query={"$filter": "IsActive eq true"})
add_request("Obtener Categorias (R_Category)", "GET", "api/v1/models/R_Category", query={"$filter": "IsActive eq true"})
add_request("Obtener Tipos de Solicitud (R_RequestType)", "GET", "api/v1/models/R_RequestType", query={"$filter": "IsActive eq true"})
add_request("Obtener Grupos (R_Group)", "GET", "api/v1/models/R_Group", query={"$filter": "IsActive eq true"})
add_request("Obtener Proyectos (C_Project)", "GET", "api/v1/models/C_Project", query={"$filter": "IsActive eq true", "$expand": "C_BPartner_ID($select=Name)"})
add_request("Obtener Tareas de Proyecto (C_ProjectTask)", "GET", "api/v1/models/C_ProjectTask", query={"$filter": "C_Project_ID eq 1000000"})
add_request("Obtener Fases de Proyecto (C_ProjectPhase)", "GET", "api/v1/models/C_ProjectPhase", query={"$filter": "C_Project_ID eq 1000000"})

# Creacion / Modificacion (POST, PUT, DELETE)
add_request("Crear Solicitud", "POST", "api/v1/models/R_Request", body={
    "Summary": "Resumen del ticket",
    "Result": "Cuerpo del ticket",
    "C_BPartner_ID": 1000013,
    "R_RequestType_ID": 1000000,
    "R_Status_ID": 1000000
})

add_request("Actualizar Solicitud", "PUT", "api/v1/models/R_Request/1000000", body={
    "Summary": "Nuevo resumen",
    "R_Status_ID": 1000001
})

add_request("Crear Actualización (Respuesta)", "POST", "api/v1/models/R_RequestUpdate", body={
    "R_Request_ID": 1000000,
    "Result": "<p><strong>Etiquetados:</strong> @Usuario</p> Respuesta aquí",
    "ConfidentialTypeEntry": "C"
})

add_request("Eliminar Solicitud", "DELETE", "api/v1/models/R_Request/1000000")
add_request("Eliminar Actualización", "DELETE", "api/v1/models/R_RequestUpdate/1000000")

# Procesos
add_request("Enviar Correo", "POST", "api/v1/processes/SendMail", body={
    "R_Request_ID": 1000000,
    "AD_User_ID": 1000000,
    "MailTemplateType": "Update"
})

with open('primhub_collection.json', 'w') as f:
    json.dump(collection, f, indent=2)

print("Archivo primhub_collection.json generado.")
