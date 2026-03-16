# File Processor

Una aplicación web construida con **Elixir**, **Phoenix Framework** y **Phoenix LiveView** diseñada para procesar, analizar y comparar el rendimiento de múltiples archivos de datos (CSV, JSON y LOG) de forma concurrente o secuencial con una experiencia de usuario en tiempo real.

## Características Principales

* **Interfaz Reactiva (Real-Time):** Interfaz moderna y dinámica construida con **Phoenix LiveView**, ofreciendo navegación fluida e interacciones instantáneas sin recargas de página.
* **Procesamiento Multiformato:** Análisis detallado de archivos `.csv`, `.json` y `.log` con extracción de métricas clave (ventas totales, usuarios activos, distribución de errores por hora, etc.).
* **Carga de Archivos en Vivo:** Soporte para arrastrar, soltar y seleccionar múltiples archivos directamente desde el navegador, con validación interactiva instantánea antes de procesar.
* **Gestión de Errores y Notificaciones:** Identifica y reporta errores por archivo y por línea. Incluye un sistema global de alertas flotantes (Flash/Toasts) para mantener al usuario informado en todo momento.
* **Motor de Concurrencia:** Permite ejecutar el procesamiento en modo **Secuencial** o **Paralelo** (aprovechando el modelo de procesos de Erlang/Elixir) e incluye un modo **Benchmark** para comparar el rendimiento de ambos métodos.
* **Persistencia Integral (Historial):** Guarda cada ejecución, incluyendo métricas consolidadas y el reporte de texto completo, en una base de datos **PostgreSQL** utilizando campos `JSONB`.
* **Reconstrucción Dinámica de Vistas:** Capacidad para consultar el historial y recrear la vista interactiva original (con pestañas y tablas de resultados) a partir de los datos almacenados.

## Tecnologías Utilizadas

* **Backend:** Elixir, Phoenix Framework
* **Frontend:** Phoenix LiveView, HTML5, CSS (Diseño responsivo y moderno)
* **Base de Datos:** PostgreSQL, Ecto
* **Testing:** ExUnit

## Requisitos Previos

Para ejecutar este proyecto localmente, necesitarás tener instalado:

* [Elixir](https://elixir-lang.org/install.html) (v1.14 o superior)
* [Erlang/OTP](https://www.erlang.org/downloads)
* [PostgreSQL](https://www.postgresql.org/download/)
* Entorno Linux/Unix recomendado (desarrollado y probado en Fedora Linux)

## 🚀 Instalación y Ejecución

1. **Clonar el repositorio:**
   ```bash
   git clone [https://github.com/AngelMartinezAguilar0211/file_processor.git](https://github.com/AngelMartinezAguilar0211/file_processor.git)
   cd file_processor
2.  **Instalar dependencias:**
    ```bash
    mix deps.get
    ```
3.  **Configurar la base de datos:**
    ```bash
      mix ecto.setup
    ```
4.  **Iniciar el servidor Phoenix:**
    ```bash
    mix phx.server
    ```
##    Pruebas

Para ejecutar las pruebas y verificar que la lógica de negocio y la base de datos funcionan correctamente:
```bash
  mix test
```
Autor: Angel Martinez Aguilar

## NOTAS IMPORTANTES

- Con el objetivo de permitir la visualización de la barra de progreso de los archivos, se decidió colocar un ligero delay de medio segundo al iniciar el proceso.
- Debido a limitaciones de los navegadores, cuando se realizan procesamientos de cientos de archivos, la única forma de ejecutar el programa es escribiendo manualmente la ruta del directorio deseado.
