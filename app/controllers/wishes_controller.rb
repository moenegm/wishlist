class WishesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_wish, only: %i[ show edit update destroy ]

  # GET /wishes or /wishes.json
  def index
    @wishes = current_user.wishes.includes(:wlist)
  end

  # GET /wishes/1 or /wishes/1.json
  def show
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
      format.html { redirect_to wishes_url, notice: "Wish was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_wish
      @wish = current_user.wishes.find(params[:id])
    end

    def assign_wlist
      return unless wish_params.key?(:wlists_id)

      @wish.wlist = current_user.wlists.find_by(id: wish_params[:wlists_id])
    end

    # Only allow a list of trusted parameters through.
    def wish_params
      params.require(:wish).permit(:title, :location, :price, :wlists_id)
    end
end
