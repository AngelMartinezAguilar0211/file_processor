# 🚀 File Processor

Una aplicación web construida con **Elixir** y el **Phoenix Framework** diseñada para procesar, analizar y comparar el rendimiento de múltiples archivos de datos (CSV, JSON y LOG) de forma concurrente o secuencial.

## ✨ Características Principales

* **Procesamiento Multiformato:** Análisis detallado de archivos `.csv`, `.json` y `.log` con extracción de métricas clave (ventas totales, usuarios activos, distribución de errores por hora, etc.).
* **Gestión de Errores Resiliente:** Identifica y reporta errores por archivo y por línea sin detener el procesamiento del resto del lote.
* **Motor de Concurrencia:** Permite ejecutar el procesamiento en modo **Secuencial** o **Paralelo** (aprovechando el modelo de procesos de Erlang/Elixir) e incluye un modo **Benchmark** para comparar el rendimiento de ambos métodos.
* **Interfaz Web Moderna:** Dashboard intuitivo con selección múltiple de archivos y visualización dinámica de resultados usando HTML/CSS y JavaScript.
* **Persistencia Integral (Historial):** Guarda cada ejecución, incluyendo métricas consolidadas y el reporte de texto completo, en una base de datos **PostgreSQL** utilizando campos `JSONB`.
* **Reconstrucción Dinámica:** Capacidad para visualizar reportes históricos recreando la vista original a partir de los datos almacenados.


## 🛠️ Tecnologías Utilizadas

* **Backend:** Elixir, Phoenix Framework
* **Base de Datos:** PostgreSQL, Ecto
* **Frontend:** HTML5, CSS, JS
* **Testing:** ExUnit

##    Requisitos Previos

Para ejecutar este proyecto localmente, necesitarás tener instalado:

* [Elixir](https://elixir-lang.org/install.html) (v1.14 o superior)
* [Erlang/OTP](https://www.erlang.org/downloads)
* [PostgreSQL](https://www.postgresql.org/download/)
* Entorno Linux/Unix recomendado (desarrollado y probado en Fedora Linux)

## 🚀 Instalación y Ejecución

1. **Clonar el repositorio:**
   ```bash
   git clone https://github.com/AngelMartinezAguilar0211/file_processor.git
   cd file_processor
    ```
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
