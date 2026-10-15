class WlistsController < ApplicationController
  before_action :authenticate_user!, except: :show
  before_action :set_wlist, only: %i[show edit update destroy]
  before_action :ensure_wlist_is_visible, only: :show

  def index
    @wlists = current_user.wlists.includes(:wishes).order(created_at: :desc)
  end

  def show
    @own_wlist = user_signed_in? && @wlist.user_id == current_user.id
  end

  def new
    @wlist = current_user.wlists.new
  end

  def edit
  end

  def create
    @wlist = current_user.wlists.new(wlist_params)

    if @wlist.save
      redirect_to @wlist, notice: "Wishlist created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @wlist.update(wlist_params)
      redirect_to @wlist, notice: "Wishlist updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @wlist.destroy
      redirect_to wlists_url, notice: "Wishlist deleted."
    else
      redirect_to @wlist, alert: "Delete the wishes in this wishlist before deleting it."
    end
  end

  private

  def set_wlist
    @wlist = if action_name == "show"
      Wlist.includes(:user, :wishes).find(params[:id])
    else
      current_user.wlists.find(params[:id])
    end
  end

  def ensure_wlist_is_visible
    return if @wlist.is_public? || (user_signed_in? && @wlist.user_id == current_user.id)

    raise ActiveRecord::RecordNotFound
  end

  def wlist_params
    params.require(:wlist).permit(:title, :wl_category, :is_public)
  end
end
