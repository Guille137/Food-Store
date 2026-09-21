DUIA - Parte 1: restricciones de integridad
Campo	Registro
Herramienta	Codex (asistente de IA), modelo/proveedor según configuración de la sesión.
Spec o prompt utilizado	"Sobre el esquema Food Store, crear reglas para: 
1) permitir sólo PENDIENTE→CONFIRMADO/CANCELADO y CONFIRMADO→ENTREGADO/CANCELADO; 
2) impedir editar detalles si el pedido no está PENDIENTE; 
3) impedir detalles de producto inactivo o con cantidad mayor al stock."
Qué generó	restricciones_food_store.sql con tres funciones PL/pgSQL y tres triggers; pruebas_restricciones.sql con pruebas válidas e inválidas.
Qué se aceptó	Las validaciones por trigger y el uso de SAVEPOINT para continuar luego de una prueba que debe fallar.
Qué se modificó o descartó, y por qué	Antes de ejecutar, revisar nombres de ids y decidir si un pedido CONFIRMADO puede pasar a CANCELADO: esta entrega lo permite porque el esquema no define una política contraria. No se incluyó descuento ni descuento de stock, ya que esas columnas y esa operación no existen en el esquema entregado.
Verificación realizada	Ejecutar pruebas_restricciones.sql sobre una copia, con ids existentes. Registrar abajo el resultado real de cada sentencia antes de hacer commit.
Resultado real pendiente de registrar
No se conectó una base desde este entorno. Tras ejecutar las pruebas, pegar aquí la salida de UPDATE, cada ERROR:, y la consulta de verificación correspondiente. No afirmar que una prueba pasó antes de observarla en PostgreSQL.