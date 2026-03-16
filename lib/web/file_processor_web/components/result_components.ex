defmodule FileProcessorWeb.ResultsComponents do
  use Phoenix.Component

  # Renders the main results wrapper and tab navigation
  def results_view(assigns) do
    ~H"""
    <div class="results-container">
      <%= if Map.get(@result, :benchmark) do %>
        <.benchmark_results result={@result} />
      <% else %>
        <h2 class="results-header">Resultados del Procesamiento</h2>

        <div class="tabs-container">
          <div class="tabs-header">
            <button
              class={"tab-button " <> if @active_tab == "summary", do: "active", else: ""}
              phx-click="set_tab"
              phx-value-tab="summary"
            >
              Resumen
            </button>
            <button
              class={"tab-button " <> if @active_tab == "html", do: "active", else: ""}
              phx-click="set_tab"
              phx-value-tab="html"
            >
              Reporte Detallado
            </button>

            <%= if get_in(@result, [:report_data, :counts, :failed]) > 0 do %>
              <button
                class={"tab-button " <> if @active_tab == "errors", do: "active", else: ""}
                phx-click="set_tab"
                phx-value-tab="errors"
                style="color: #dc2626; font-weight: 600;"
              >
                Errores por Archivo
              </button>
            <% end %>

            <button
              class={"tab-button " <> if @active_tab == "full", do: "active", else: ""}
              phx-click="set_tab"
              phx-value-tab="full"
            >
              Archivo Texto
            </button>
          </div>

          <%= case @active_tab do %>
            <% "summary" -> %>
              <.tab_summary result={@result} />
            <% "html" -> %>
              <.tab_detailed_report result={@result} />
            <% "errors" -> %>
              <.tab_errors result={@result} />
            <% "full" -> %>
              <.tab_raw_file result={@result} />
            <% _ -> %>
              <.tab_summary result={@result} />
          <% end %>
        </div>

        <div class="action-buttons">
          <.link href="/" class="btn-primary">Procesar Nuevo Archivo</.link>
        </div>
      <% end %>
    </div>
    """
  end

  # Renders the benchmark mode results
  def benchmark_results(assigns) do
    ~H"""
    <div class="section-header">
      <h2>Resultados del Benchmark</h2>
      <span class="status-badge" style="background: #e0e7ff; color: #4f46e5;">
        Comparación de Rendimiento
      </span>
    </div>

    <div style="background: linear-gradient(135deg, #4f46e5 0%, #3730a3 100%); color: white; border-radius: 8px; padding: 2rem; text-align: center; margin-bottom: 2rem; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.1);">
      <h3 style="margin-top: 0; color: #e0e7ff; font-weight: 500;">Factor de Aceleración</h3>
      <div style="font-size: 3.5rem; font-weight: 800; line-height: 1;">
        {Float.round(@result[:results].speedup, 2)}x
      </div>
      <p style="margin-bottom: 0; margin-top: 0.5rem; color: #c7d2fe; font-size: 1.125rem;">
        <%= if @result[:results].speedup > 1.0 do %>
          El procesamiento paralelo fue más rápido.
        <% else %>
          El procesamiento secuencial fue más rápido.
        <% end %>
      </p>
    </div>

    <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.5rem; margin-bottom: 2rem;">
      <div
        class="summary-section"
        style="border-top: 4px solid #64748b; background: #f8fafc; margin-bottom: 0;"
      >
        <h3 style="color: #475569; margin-top: 0; display: flex; align-items: center; justify-content: space-between;">
          <span>Modo Secuencial</span>
          <span style="font-size: 1.5rem;">⏱️</span>
        </h3>
        <div style="font-size: 2rem; font-weight: bold; color: #0f172a; margin: 1rem 0;">
          {Float.round(@result[:results].sequential_time * 1000, 2)}
          <span style="font-size: 1rem; color: #64748b;">ms</span>
        </div>
      </div>

      <div
        class="summary-section"
        style="border-top: 4px solid #10b981; background: #ecfdf5; margin-bottom: 0;"
      >
        <h3 style="color: #047857; margin-top: 0; display: flex; align-items: center; justify-content: space-between;">
          <span>Modo Paralelo</span>
          <span style="font-size: 1.5rem;">⚡</span>
        </h3>
        <div style="font-size: 2rem; font-weight: bold; color: #064e3b; margin: 1rem 0;">
          {Float.round(@result[:results].parallel_time * 1000, 2)}
          <span style="font-size: 1rem; color: #047857;">ms</span>
        </div>
      </div>
    </div>

    <div class="actions-container">
      <.link href="/" class="btn-primary">⬅️ Volver al Inicio</.link>
    </div>
    """
  end

  # Renders the executive summary tab
  def tab_summary(assigns) do
    ~H"""
    <div>
      <div class="section-header">
        <h2>Resumen Ejecutivo</h2>
        <%= if @result[:report_data].counts.failed == 0 do %>
          <span class="status-badge success">Completado sin errores</span>
        <% else %>
          <span class="status-badge" style="background: #fee2e2; color: #991b1b;">
            Completado con errores
          </span>
        <% end %>
      </div>

      <div
        class="processing-info"
        style="margin-bottom: 2rem; background: #f8fafc; border: 1px solid #e2e8f0;"
      >
        <div class="info-row">
          <span class="info-label">Modo de Procesamiento:</span>
          <span class="info-value">{String.capitalize(to_string(@result[:mode]))}</span>
        </div>
        <div class="info-row">
          <span class="info-label">Ruta del Reporte:</span>
          <span class="info-value code">{Path.basename(to_string(@result[:report_path]))}</span>
        </div>
      </div>

      <div class="metrics-summary">
        <div class="metric-card">
          <div class="metric-label">Total Procesados</div>
          <div class="metric-value">{@result[:report_data].counts.total}</div>
        </div>

        <div
          class="metric-card"
          style="background: linear-gradient(135deg, #10b981 0%, #059669 100%);"
        >
          <div class="metric-label">Exitosos</div>
          <div class="metric-value">{@result[:report_data].counts.ok}</div>
        </div>

        <div
          class="metric-card"
          style={
            if @result[:report_data].counts.failed > 0,
              do: "background: linear-gradient(135deg, #ef4444 0%, #b91c1c 100%);",
              else: "background: linear-gradient(135deg, #9ca3af 0%, #6b7280 100%);"
          }
        >
          <div class="metric-label">Con Errores</div>
          <div class="metric-value">{@result[:report_data].counts.failed}</div>
        </div>

        <div class="metric-card">
          <div class="metric-label">Tiempo Total</div>
          <div class="metric-value">
            {Float.round(@result[:report_data].elapsed_seconds * 1000, 2)} ms
          </div>
        </div>

        <% success_rate =
          if @result[:report_data].counts.total > 0,
            do: @result[:report_data].counts.ok * 100.0 / @result[:report_data].counts.total,
            else: 0.0 %>
        <div
          class="metric-card"
          style="background: linear-gradient(135deg, #f59e0b 0%, #d97706 100%);"
        >
          <div class="metric-label">Tasa de Éxito</div>
          <div class="metric-value">{Float.round(success_rate, 1)}%</div>
        </div>

        <%= if @result[:report_data].counts.csv > 0 do %>
          <div
            class="metric-card"
            style="background: linear-gradient(135deg, #4f46e5 0%, #3730a3 100%);"
          >
            <div class="metric-label">Archivos CSV</div>
            <div class="metric-value">{@result[:report_data].counts.csv}</div>
          </div>
        <% end %>

        <%= if @result[:report_data].counts.json > 0 do %>
          <div
            class="metric-card"
            style="background: linear-gradient(135deg, #059669 0%, #047857 100%);"
          >
            <div class="metric-label">Archivos JSON</div>
            <div class="metric-value">{@result[:report_data].counts.json}</div>
          </div>
        <% end %>

        <%= if @result[:report_data].counts.log > 0 do %>
          <div
            class="metric-card"
            style="background: linear-gradient(135deg, #d97706 0%, #b45309 100%);"
          >
            <div class="metric-label">Archivos LOG</div>
            <div class="metric-value">{@result[:report_data].counts.log}</div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  # Renders the detailed breakdown metrics per file type
  def tab_detailed_report(assigns) do
    ~H"""
    <div>
      <%= if @result[:report_data].counts.csv > 0 do %>
        <div
          class="summary-section"
          style="margin-bottom: 2rem; background: #eef2ff; border: 1px solid #c7d2fe;"
        >
          <h3 style="border-bottom: 2px solid #a5b4fc; padding-bottom: 0.5rem; color: #3730a3;">
            Métricas de Archivos CSV
          </h3>
          <%= for file <- @result[:report_data].csv_files do %>
            <div class="processing-info" style="margin-top: 1rem; background: rgba(255,255,255,0.7);">
              <h4 style="margin-top: 0; color: #4f46e5; font-family: monospace;">
                [Archivo: {Path.basename(file.path)}]
              </h4>
              <%= if file.status == :ok do %>
                <div style="display: flex; flex-direction: column;">
                  <div class="info-row" style="border-bottom: 1px dashed #c7d2fe;">
                    <span class="info-label">Ventas Totales:</span><span class="info-value font-bold">${Float.round(file.metrics.total_sales, 2)}</span>
                  </div>
                  <div class="info-row" style="border-bottom: 1px dashed #c7d2fe;">
                    <span class="info-label">Productos Únicos:</span><span class="info-value">{file.metrics.unique_products}</span>
                  </div>
                  <div class="info-row" style="border-bottom: 1px dashed #c7d2fe;">
                    <span class="info-label">Mejor Producto:</span>
                    <span class="info-value">
                      {if file.metrics.top_product,
                        do:
                          "#{file.metrics.top_product.name} (#{file.metrics.top_product.value} uds)",
                        else: "N/A"}
                    </span>
                  </div>
                  <div class="info-row" style="border-bottom: 1px dashed #c7d2fe;">
                    <span class="info-label">Categoría Principal:</span>
                    <span class="info-value">
                      {if file.metrics.top_category,
                        do:
                          "#{file.metrics.top_category.name} ($#{Float.round(file.metrics.top_category.value, 2)})",
                        else: "N/A"}
                    </span>
                  </div>
                  <div class="info-row">
                    <span class="info-label">Descuento Promedio:</span><span class="info-value">{Float.round(file.metrics.avg_discount_pct, 2)}%</span>
                  </div>
                </div>
              <% else %>
                <div style="color: #dc2626; font-weight: 500; padding: 0.5rem; background: #fee2e2; border-radius: 4px;">
                  Se encontraron errores (Ver pestaña 'Errores por Archivo')
                </div>
              <% end %>
            </div>
          <% end %>
          <div
            class="processing-info"
            style="margin-top: 1rem; background: #e0e7ff; border-left: 4px solid #4f46e5;"
          >
            <h4 style="margin-top: 0; color: #3730a3;">Totales Consolidados CSV</h4>
            <div style="display: flex; flex-direction: column;">
              <div class="info-row">
                <span class="info-label">Ventas Totales:</span><span class="info-value font-bold">${Float.round(@result[:report_data].csv_totals.total_sales, 2)}</span>
              </div>
              <div class="info-row">
                <span class="info-label">Productos Únicos Totales:</span><span class="info-value">{@result[:report_data].csv_totals.unique_products}</span>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @result[:report_data].counts.json > 0 do %>
        <div
          class="summary-section"
          style="margin-bottom: 2rem; background: #ecfdf5; border: 1px solid #a7f3d0;"
        >
          <h3 style="border-bottom: 2px solid #6ee7b7; padding-bottom: 0.5rem; color: #065f46;">
            Métricas de Archivos JSON
          </h3>
          <%= for file <- @result[:report_data].json_files do %>
            <div class="processing-info" style="margin-top: 1rem; background: rgba(255,255,255,0.7);">
              <h4 style="margin-top: 0; color: #059669; font-family: monospace;">
                [Archivo: {Path.basename(file.path)}]
              </h4>
              <%= if file.status == :ok do %>
                <div style="display: flex; flex-direction: column;">
                  <div class="info-row" style="border-bottom: 1px dashed #a7f3d0;">
                    <span class="info-label">Usuarios Registrados:</span><span class="info-value">{file.metrics.total_users}</span>
                  </div>
                  <div class="info-row" style="border-bottom: 1px dashed #a7f3d0;">
                    <span class="info-label">Usuarios Activos:</span><span class="info-value">{file.metrics.active_users}</span>
                  </div>
                  <div class="info-row" style="border-bottom: 1px dashed #a7f3d0;">
                    <span class="info-label">Usuarios Inactivos:</span><span class="info-value">{file.metrics.inactive_users}</span>
                  </div>
                  <div class="info-row" style="border-bottom: 1px dashed #a7f3d0;">
                    <span class="info-label">Duración Promedio Sesión:</span><span class="info-value">{Float.round(file.metrics.avg_session_seconds / 60.0, 2)} min</span>
                  </div>
                  <div class="info-row">
                    <span class="info-label">Páginas Visitadas:</span><span class="info-value">{file.metrics.total_pages}</span>
                  </div>
                </div>
              <% else %>
                <div style="color: #dc2626; font-weight: 500; padding: 0.5rem; background: #fee2e2; border-radius: 4px;">
                  Se encontraron errores (Ver pestaña 'Errores por Archivo')
                </div>
              <% end %>
            </div>
          <% end %>
          <div
            class="processing-info"
            style="margin-top: 1rem; background: #d1fae5; border-left: 4px solid #059669;"
          >
            <h4 style="margin-top: 0; color: #065f46;">Totales Consolidados JSON</h4>
            <div style="display: flex; flex-direction: column;">
              <div class="info-row">
                <span class="info-label">Usuarios Totales:</span><span class="info-value font-bold">{@result[:report_data].json_totals.total_users}</span>
              </div>
              <div class="info-row">
                <span class="info-label">Activos:</span><span class="info-value">{@result[:report_data].json_totals.active_users}</span>
              </div>
              <div class="info-row">
                <span class="info-label">Inactivos:</span><span class="info-value">{@result[:report_data].json_totals.inactive_users}</span>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%= if @result[:report_data].counts.log > 0 do %>
        <div
          class="summary-section"
          style="margin-bottom: 2rem; background: #fffbeb; border: 1px solid #fde68a;"
        >
          <h3 style="border-bottom: 2px solid #fcd34d; padding-bottom: 0.5rem; color: #92400e;">
            Métricas de Archivos LOG
          </h3>
          <%= for file <- @result[:report_data].log_files do %>
            <div class="processing-info" style="margin-top: 1rem; background: rgba(255,255,255,0.7);">
              <h4 style="margin-top: 0; color: #d97706; font-family: monospace;">
                [Archivo: {Path.basename(file.path)}]
              </h4>
              <%= if file.status == :ok do %>
                <div style="display: flex; flex-direction: column;">
                  <div class="info-row" style="border-bottom: 1px dashed #fde68a;">
                    <span class="info-label">Entradas Totales:</span><span class="info-value font-bold">{file.metrics.total_entries}</span>
                  </div>
                  <div class="info-row">
                    <span class="info-label">Componente con más errores:</span>
                    <span class="info-value">
                      {if file.metrics.top_error_component,
                        do:
                          "#{file.metrics.top_error_component.name} (#{file.metrics.top_error_component.value})",
                        else: "N/A"}
                    </span>
                  </div>
                </div>
                <div style="margin-top: 1rem; padding-top: 0.5rem; border-top: 1px solid #fde68a;">
                  <strong style="color: #92400e; font-size: 0.875rem;">
                    Errores más frecuentes:
                  </strong>
                  <ul style="margin-top: 0.5rem; font-size: 0.875rem; color: #4b5563;">
                    <%= if length(file.metrics.top_error_messages) > 0 do %>
                      <%= for {err, index} <- Enum.with_index(file.metrics.top_error_messages, 1) do %>
                        <li>{index}. {err.message} ({err.count})</li>
                      <% end %>
                    <% else %>
                      <li>Ninguno</li>
                    <% end %>
                  </ul>
                </div>
              <% else %>
                <div style="color: #dc2626; font-weight: 500; padding: 0.5rem; background: #fee2e2; border-radius: 4px;">
                  Se encontraron errores (Ver pestaña 'Errores por Archivo')
                </div>
              <% end %>
            </div>
          <% end %>
          <div
            class="processing-info"
            style="margin-top: 1rem; background: #fef3c7; border-left: 4px solid #d97706;"
          >
            <h4 style="margin-top: 0; color: #92400e;">Totales Consolidados LOG</h4>
            <div class="info-row">
              <span class="info-label">Entradas Totales:</span><span class="info-value font-bold">{@result[:report_data].log_totals.total_entries}</span>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Renders the exact error breakdown per file when processing issues arise
  def tab_errors(assigns) do
    ~H"""
    <div class="summary-section" style="background: #fef2f2; border: 1px solid #fecaca;">
      <h3 style="color: #b91c1c; border-bottom: 2px solid #fca5a5; padding-bottom: 0.5rem; margin-top: 0;">
        Detalle de Errores en Archivos
      </h3>
      <%= for file <- @result[:report_data].csv_files ++ @result[:report_data].json_files ++ @result[:report_data].log_files, file.status != :ok do %>
        <div
          class="processing-info"
          style="margin-top: 1rem; background: white; border-left: 4px solid #ef4444; box-shadow: 0 1px 3px rgba(0,0,0,0.1);"
        >
          <h4 style="margin-top: 0; color: #b91c1c; font-family: monospace; display: flex; justify-content: space-between;">
            <span>[Archivo: {Path.basename(file.path)}]</span>
            <span
              class="status-badge"
              style="background: #fee2e2; color: #991b1b; padding: 0.25rem 0.5rem;"
            >
              {String.upcase(to_string(file.status))}
            </span>
          </h4>
          <ul style="color: #dc2626; font-size: 0.875rem; padding-left: 1.5rem; margin-bottom: 0; font-family: monospace;">
            <%= if length(Map.get(file, :errors, [])) > 0 do %>
              <%= for error <- file.errors do %>
                <li style="margin-bottom: 0.25rem;">
                  <%= if Map.get(error, :line) do %>
                    <span style="font-weight: 600; color: #991b1b;">
                      Línea {Map.get(error, :line)}:
                    </span>
                  <% end %>
                  {Map.get(error, :error, inspect(error))}
                </li>
              <% end %>
            <% else %>
              <% critical_errors =
                Enum.filter(@result[:report_data].errors, fn e -> e.path == file.path end) %>
              <%= for error <- critical_errors do %>
                <li style="margin-bottom: 0.25rem;">{Map.get(error, :error, inspect(error))}</li>
              <% end %>
              <%= if length(critical_errors) == 0 do %>
                <li style="margin-bottom: 0.25rem;">
                  Error crítico de procesamiento. Verifica el archivo log.
                </li>
              <% end %>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
    """
  end

  # Renders the full raw text structure of the file report
  def tab_raw_file(assigns) do
    ~H"""
    <div class="report-viewer">
      <pre class="report-content" id="full-report">
        <%= if @result[:report_text] do %>
          <%= @result[:report_text] %>
        <% else %>
          <%= @result[:content] %>
        <% end %>
      </pre>
    </div>
    """
  end
end
