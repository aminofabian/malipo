defmodule MalipoWeb.Admin.TeamLive do
  @moduledoc """
  Super-admin team — DB-backed console operators. Route: `/admin/team`.

  The env break-glass credential (`MALIPO_ADMIN_USER`/`MALIPO_ADMIN_PASSWORD`)
  is not listed here; it always works and is what gets you in the first time.
  """

  use MalipoWeb, :live_view

  alias Malipo.AdminUsers
  alias Malipo.AdminUsers.AdminUser

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Team")
     |> assign(:new_form, new_form())
     |> assign(:resetting, nil)
     |> assign(:password_form, nil)
     |> load()}
  end

  @impl true
  def handle_event("validate", %{"admin_user" => params}, socket) do
    changeset =
      AdminUser.create_changeset(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :new_form, to_form(changeset, as: :admin_user))}
  end

  def handle_event("save", %{"admin_user" => params}, socket) do
    case AdminUsers.create(params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "Added #{user.email}")
         |> assign(:new_form, new_form())
         |> load()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         assign(socket, :new_form, to_form(Map.put(changeset, :action, :insert), as: :admin_user))}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    case AdminUsers.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Operator not found")}

      %AdminUser{} = user ->
        toggle(socket, user)
    end
  end

  def handle_event("reset", %{"id" => id}, socket) do
    case AdminUsers.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Operator not found")}

      %AdminUser{} = user ->
        changeset = AdminUser.password_changeset(user, %{})

        {:noreply,
         socket
         |> assign(:resetting, user.id)
         |> assign(:password_form, to_form(changeset, as: :password))}
    end
  end

  def handle_event("cancel_reset", _params, socket) do
    {:noreply, assign(socket, resetting: nil, password_form: nil)}
  end

  def handle_event("save_password", %{"password" => params} = payload, socket) do
    id = payload["reset_id"] || socket.assigns.resetting

    case AdminUsers.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Operator not found")}

      %AdminUser{} = user ->
        case AdminUsers.update_password(user, params) do
          {:ok, updated} ->
            {:noreply,
             socket
             |> put_flash(:info, "Password updated for #{updated.email}")
             |> assign(resetting: nil, password_form: nil)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             assign(
               socket,
               :password_form,
               to_form(Map.put(changeset, :action, :insert), as: :password)
             )}
        end
    end
  end

  defp toggle(socket, %AdminUser{active: true} = user) do
    cond do
      self?(socket, user) ->
        {:noreply, put_flash(socket, :error, "You cannot deactivate your own account")}

      last_active?(user) ->
        {:noreply, put_flash(socket, :error, "At least one operator must stay active")}

      true ->
        {:ok, _} = AdminUsers.set_active(user, false)

        {:noreply,
         socket
         |> put_flash(:info, "Deactivated #{user.email}")
         |> load()}
    end
  end

  defp toggle(socket, %AdminUser{} = user) do
    {:ok, _} = AdminUsers.set_active(user, true)

    {:noreply,
     socket
     |> put_flash(:info, "Reactivated #{user.email}")
     |> load()}
  end

  defp self?(socket, %AdminUser{} = user) do
    case socket.assigns[:current_admin] do
      admin when is_binary(admin) -> String.downcase(admin) == user.email
      _ -> false
    end
  end

  defp last_active?(%AdminUser{} = user) do
    user.active and
      AdminUsers.list()
      |> Enum.count(& &1.active) <= 1
  end

  defp load(socket) do
    assign(socket, :users, AdminUsers.list())
  end

  defp new_form do
    AdminUser.create_changeset(%{}) |> to_form(as: :admin_user)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current={:team} admin={@current_admin}>
      <div class="mb-6">
        <h1 class="text-2xl font-semibold tracking-tight">Team</h1>
        <p class="mt-1 text-sm text-base-content/60">
          Operators who can sign in to this console. The break-glass credential from
          the environment is not listed here.
        </p>
      </div>

      <div class="overflow-x-auto">
        <table class="table table-sm">
          <thead>
            <tr class="text-base-content/50">
              <th>Operator</th>
              <th>Role</th>
              <th>Status</th>
              <th>Last login</th>
              <th>Added</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={user <- @users} id={"admin-user-#{user.id}"} class="hover:bg-base-200/40">
              <td>
                <span class="font-medium">{user.email}</span>
                <span :if={user.name} class="mt-0.5 block text-xs text-base-content/50">
                  {user.name}
                </span>
              </td>
              <td class="text-xs">{user.role}</td>
              <td>
                <span class={[
                  "badge badge-sm",
                  user.active && "badge-success",
                  !user.active && "badge-ghost"
                ]}>
                  {if user.active, do: "active", else: "disabled"}
                </span>
              </td>
              <td class="whitespace-nowrap text-xs text-base-content/50">
                {fmt(user.last_login_at)}
              </td>
              <td class="whitespace-nowrap text-xs text-base-content/50">{fmt(user.inserted_at)}</td>
              <td class="space-x-2 text-right whitespace-nowrap">
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="reset"
                  phx-value-id={user.id}
                >
                  Reset password
                </button>
                <button
                  type="button"
                  class="btn btn-ghost btn-xs"
                  phx-click="toggle"
                  phx-value-id={user.id}
                >
                  {if user.active, do: "Deactivate", else: "Reactivate"}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@users == []} class="py-10 text-center text-sm text-base-content/50">
        No DB operators yet — add one below, or keep using the env credential.
      </div>

      <section :if={@resetting} class="mt-8 max-w-md space-y-3 border-t border-base-300 pt-6">
        <h2 class="text-sm font-semibold">Reset password</h2>

        <.form
          for={@password_form}
          id="reset-password-form"
          phx-submit="save_password"
          class="space-y-4"
        >
          <input type="hidden" name="reset_id" value={@resetting} />
          <.input
            field={@password_form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <div class="flex gap-3">
            <button type="submit" class="btn btn-primary btn-sm" phx-disable-with="Saving…">
              Save password
            </button>
            <button type="button" class="btn btn-ghost btn-sm" phx-click="cancel_reset">Cancel</button>
          </div>
        </.form>
      </section>

      <section class="mt-8 max-w-md space-y-3 border-t border-base-300 pt-6">
        <h2 class="text-sm font-semibold">Add operator</h2>

        <.form
          for={@new_form}
          id="admin-user-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4"
        >
          <.input field={@new_form[:email]} type="email" label="Email" autocomplete="off" required />
          <.input field={@new_form[:name]} type="text" label="Name (optional)" autocomplete="off" />
          <.input
            field={@new_form[:password]}
            type="password"
            label="Password (min 8 characters)"
            autocomplete="new-password"
            required
          />
          <.input
            field={@new_form[:role]}
            type="select"
            label="Role"
            options={[Admin: "admin", Owner: "owner"]}
          />
          <button type="submit" class="btn btn-primary" phx-disable-with="Adding…">Add operator</button>
        </.form>
      </section>
    </Layouts.admin>
    """
  end

  defp fmt(nil), do: "—"
  defp fmt(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
end
