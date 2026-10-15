class WishesController < ApplicationController
  before_action :authenticate_user!, except: :show
  before_action :set_wish, only: %i[ show edit update destroy ]
  before_action :ensure_wish_is_visible, only: :show

  def show
    @own_wish = user_signed_in? && @wish.user_id == current_user.id
  end

  # GET /wishes/new
  def new
    @wish = current_user.wishes.new
    @wish.wlist = current_user.wlists.find_by(id: params[:wlists_id]) if params[:wlists_id].present?
  end

  # GET /wishes/1/edit
  def edit
  end

  # POST /wishes or /wishes.json
  def create
    @wish = current_user.wishes.new(wish_params.except(:wlists_id))
    assign_wlist

    respond_to do |format|
      if @wish.save
        notify_followers_of_public_list if @wish.wlist.is_public?
        format.html { redirect_to wish_url(@wish), notice: "Wish was successfully created." }
        format.json { render :show, status: :created, location: @wish }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @wish.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /wishes/1 or /wishes/1.json
  def update
    @wish.assign_attributes(wish_params.except(:wlists_id))
    assign_wlist

    respond_to do |format|
      if @wish.save
        format.html { redirect_to wish_url(@wish), notice: "Wish was successfully updated." }
        format.json { render :show, status: :ok, location: @wish }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @wish.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /wishes/1 or /wishes/1.json
  def destroy
    @wish.destroy

    respond_to do |format|
        format.html { redirect_to wlist_url(@wish.wlist), notice: "Wish was successfully removed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_wish
      @wish = if action_name == "show"
        Wish.includes(:wlist, :user).find(params[:id])
      else
        current_user.wishes.find(params[:id])
      end
    end

    def ensure_wish_is_visible
      return if @wish.wlist.is_public? || (user_signed_in? && @wish.user_id == current_user.id)

      raise ActiveRecord::RecordNotFound
    end

    def assign_wlist
      return unless wish_params.key?(:wlists_id)

      @wish.wlist = current_user.wlists.find_by(id: wish_params[:wlists_id])
    end

    def notify_followers_of_public_list
      @wish.wlist.user.followers.where.not(id: current_user.id).find_each do |follower|
        Notification.create!(recipient: follower, actor: current_user, event_type: "added_wish", notifiable: @wish)
      end
    end

    # Only allow a list of trusted parameters through.
    def wish_params
      params.require(:wish).permit(:title, :location, :price, :wlists_id)
    end
end
