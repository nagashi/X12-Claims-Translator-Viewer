defmodule ClaimViewer.Repo.Migrations.RenamePatientToMember do
  use Ecto.Migration

  def change do
    rename table(:claims), :patient_first_name, to: :member_first_name
    rename table(:claims), :patient_last_name, to: :member_last_name
    rename table(:claims), :patient_dob, to: :member_dob

    # Drop old indexes and create new ones with updated names
    drop_if_exists index(:claims, [:patient_first_name])
    drop_if_exists index(:claims, [:patient_last_name])
    drop_if_exists index(:claims, [:patient_dob])

    create index(:claims, [:member_first_name])
    create index(:claims, [:member_last_name])
    create index(:claims, [:member_dob])
  end
end
